import threading
import asyncio
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import AsyncIOOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient


class OSCServer:
    """A threaded OSC server using python-osc library. With a given message handler function, will call that function on incoming messages."""
    # Dictionary to store clients for sending messages
    _clients = {}
    _clients_lock = threading.Lock()
    _named_targets = {}

    def __init__(self, in_ip="0.0.0.0", port=5005, osc_msg_handler=None):
        """Initialize the OSC server with IP, port, and message handler.
        
        Args:
            in_ip (str): IP address to bind the server to. If "0.0.0.0", listens on all interfaces. This is the default. Set to a specific IP to only accept messages from that interface.
            port (int): Port number to listen on.
            osc_msg_handler (function): Function to handle incoming OSC messages.
        """

        self.in_ip = in_ip
        self.port = port
        self.thread = None
        self.stop_flag = threading.Event()
        self.transport = None
        self.osc_msg_handler = osc_msg_handler if osc_msg_handler else self.default_handler
        self.dispatcher = Dispatcher()

    def filter_handler(self, client_address, key, *args):
        if self.in_ip == "0.0.0.0" or self.in_ip == client_address[0]:
            self.osc_msg_handler(client_address, key, *args)

    def default_handler(self, client_address, key, *args):
        client_ip = client_address[0]
        client_port = client_address[1]
        if client_ip == self.in_ip:
            print(f"From {client_ip}:{client_port} | {key} | Args: {args}")
        
    def set_osc_msg_handler(self, handler):
        """Set a custom OSC message handler.
        
        Args:
            handler (function): Function to handle incoming OSC messages.
        """
        self.osc_msg_handler = handler
        self.dispatcher.set_default_handler(self.filter_handler, needs_reply_address=True)

    def start(self):
        """Start the OSC server in a separate thread"""
        if self.thread and self.thread.is_alive():
            print("Server is already running")
            return
            
        self.stop_flag.clear()
        self.thread = threading.Thread(target=self._run_server, daemon=False)
        self.thread.start()
        print("OSC Server thread started")
    
    def stop(self):
        """Stop the OSC server gracefully"""
        if not self.thread or not self.thread.is_alive():
            print("Server is not running")
            return
            
        print("Stopping OSC server...")
        self.stop_flag.set()
        
        # Wait for the thread to finish
        self.thread.join(timeout=5.0)
        
        if self.thread.is_alive():
            print("Warning: Thread did not stop gracefully")
        else:
            print("OSC Server stopped successfully")
        
    
    def _run_server(self):
        """Run the server in its own event loop"""
        asyncio.run(self._start_osc_server())
    
    async def _start_osc_server(self):
        self.dispatcher.set_default_handler(self.filter_handler, needs_reply_address=True)
        
        server = AsyncIOOSCUDPServer(("0.0.0.0", self.port), self.dispatcher, asyncio.get_event_loop())
        self.transport, protocol = await server.create_serve_endpoint()
        
        print(f"OSC Server listening on {self.in_ip}:{self.port}")
        
        try:
            while not self.stop_flag.is_set():
                await asyncio.sleep(0.1)
        except asyncio.CancelledError:
            pass
        finally:
            print("Closing OSC server transport...")
            if self.transport:
                self.transport.close()

    # ==================== SENDING METHODS ====================
    @staticmethod
    def _get_client(ip: str, port: int) -> SimpleUDPClient:
        """Get or create a client for the given ip:port combination.
        
        Args:
            ip (str): Target IP address.
            port (int): Target port number.
            
        Returns:
            SimpleUDPClient: The OSC client for sending messages.
        """
        key = (ip, port)
        with OSCServer._clients_lock:
            if key not in OSCServer._clients:
                OSCServer._clients[key] = SimpleUDPClient(ip, port)
            return OSCServer._clients[key]

    @staticmethod
    def send(key: str, *args, ip: str = "127.0.0.1", port: int = 5006):
        """Send an OSC message to a specific destination.
        
        Args:
            key (str): OSC address pattern (e.g., "/synth/freq").
            *args: Values to send with the message.
            ip (str): Target IP address. Defaults to "127.0.0.1".
            port (int): Target port number. Defaults to 5006.
            
        Example:
            server.send("/synth/freq", 440.0)
            server.send("/mixer/volume", 0.8, ip="192.168.1.100", port=9000)
            server.send("/note", 60, 127, 0.5)  # multiple values
        """
        client = OSCServer._get_client(ip, port)
        client.send_message(key, args if len(args) != 1 else args[0])
    
    @staticmethod
    def send_bundle(messages: list, ip: str = "127.0.0.1", port: int = 5006, timetag=None):
        """Send an OSC bundle (multiple messages with optional timetag).
        
        Args:
            messages (list): List of tuples (key, args) where args is a list of values.
            ip (str): Target IP address. Defaults to "127.0.0.1".
            port (int): Target port number. Defaults to 5006.
            timetag: Optional timetag for the bundle (None = immediately).
            
        Example:
            server.send_bundle([
                ("/synth/freq", [440.0]),
                ("/synth/amp", [0.8]),
                ("/synth/gate", [1])
            ])
        """
        from pythonosc.osc_bundle_builder import OscBundleBuilder, IMMEDIATELY
        from pythonosc.osc_message_builder import OscMessageBuilder
        
        bundle_builder = OscBundleBuilder(timetag if timetag else IMMEDIATELY)
        
        for address, args in messages:
            msg_builder = OscMessageBuilder(address=address)
            if args:
                for arg in args:
                    msg_builder.add_arg(arg)
            bundle_builder.add_content(msg_builder.build())
        
        bundle = bundle_builder.build()
        client = OSCServer._get_client(ip, port)
        client.send(bundle)
    
    @staticmethod
    def add_target(name: str, ip: str, port: int):
        """Register a named target for easier sending.
        
        Args:
            name (str): Friendly name for the target.
            ip (str): Target IP address.
            port (int): Target port number.
            
        Example:
            server.add_target("synth", "192.168.1.100", 9000)
            server.send_to("synth", "/freq", 440.0)
        """

        OSCServer._named_targets[name] = (ip, port)
        OSCServer._get_client(ip, port)
    
    @staticmethod
    def send_to(target_name: str, key: str, *args):
        """Send an OSC message to a named target.
        
        Args:
            target_name (str): Name of a registered target.
            key (str): OSC address pattern.
            *args: Values to send with the message.
            
        Example:
            server.send_to("synth", "/freq", 440.0)
        """

        ip, port = OSCServer._named_targets[target_name]
        OSCServer.send(key, *args, ip=ip, port=port)