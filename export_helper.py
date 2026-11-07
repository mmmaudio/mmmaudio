
import os

target_graph = None
target_package = None
plugin_name = None
install = False
plugin_format = None
is_instrument = None
in_labels = None
out_labels = None

def main():
    
    print("""
          ||=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=||
          ||                                                         ||
          ||    🔥⚡   MMMAudio Interactive Graph Exporter   ⚡🔥    ||
          ||                                                         ||       
          ||=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=||
          """)
    
    builds = input("Do you want to export the graph as a plugin, SuperCollider UGEN, VCV Rack, or all? (PLUGIN/ugen/vcv/all): ")
    
    if not builds:
        builds = ["PLUGIN"]
    else:
        builds = builds.split()
    for i in range(len(builds)):
        builds[i] = builds[i].upper()
    
    target_package = input("Target package: ")
    target_graph = input("Name of target graph: ")
    plugin_name = input("What is the name of your plugin/ugen/module? (Default is None): ")
    is_instrument = input("Would you like to build the plugin/ugen/module as an instrument? y/N: ")
    path_to_gui = input("Path to GUI file. If there is no path given, default GUI will be created: ")
    path_to_resources = input("Paths to resource files (Default is None): ")
    config = input("CMake Config ('RELEASE'/'debug'): ")
    build = input("Build the graph now? (You will need to build them yourself using CMake later if you select n). Y/n: ")
    path_to_resources = tuple(path_to_resources.split())
    
    
    if not config:
        config = "Release"
    elif config.upper() == "RELEASE":
        config = "Release"
    elif config.upper() == "DEBUG":
        config = "Debug"
    
   

    if is_instrument.upper() == "Y"  or is_instrument.upper() == "YES":
        is_instrument = True

    for plugin_type in builds:
        if  plugin_type == "PLUGIN" or plugin_type == "ALL":
            plugin_questions()
            from Exporters.PluginExporter.export_plugin import export_plugin
            print("building plugin with: ", target_graph ,
                target_package ,
                plugin_name ,
                install ,
                plugin_format ,
                is_instrument )
            
            export_plugin(
                graph_name=target_graph, 
                package_name=target_package,
                plugin_name=plugin_name,
                plugin_type=plugin_format,
                resources=path_to_resources,
                install=install,
                config=config,
                instrument=is_instrument
                )
        
        if plugin_type == "UGEN" or plugin_type == "ALL":
            from Exporters.SCExporter.export_sc import export_sc
            ugen_questions()
            export_sc(
                graph_name=target_graph,
                package_name=target_package,
                gui_file=path_to_gui,
                ugen_name=plugin_name,
                resources=path_to_resources,
                install=install,
                config=config
                
            )
    
        if plugin_type == "VCV" or plugin_type == "ALL":
            from Exporters.VCVExporter.export_vcv import export_vcv 
            in_labels, out_labels = vcv_questions()
            
            if not in_labels:
                in_lables = []
            else:
                in_labels = in_labels.split()
                
            if not out_labels:
                out_lables = []
            else:
                out_labels = out_labels.split()
                
            print(in_labels, out_labels)
            
            export_vcv(
                graph_name=target_graph,
                package_name=target_package,
                gui_file=path_to_gui,
                module_name=plugin_name,
                num_in = len(in_labels),
                num_out = len(out_labels),
                resources=path_to_resources,
                install=install,
                out_labels= out_labels,
                in_labels= in_labels
            )
    



def plugin_questions():
        install = input("Would you like to install the compiled plugin? y/N: ")
        plugin_format = input("What kind of plugin would you like to build? Multiple plugin types can be selected by separating them with spaces. Default is VST3 ('VST3'/'AU'/'Clap'): ")
        

    
        if not plugin_format:
            plugin_format = ["VST3"]
        else:
            plugin_format = plugin_format.split()
            pass
        
        
            
        
        if not install:
            install = False
        elif install.upper() != "N" or install.upper() != "YES":
            install = False
    
def ugen_questions():
        install = input("Would you like to install the compiled ugen? y/N: ")
        
    
        
        
        if not install:
            install = False
        elif install.upper() != "N" or install.upper() != "YES":
            install = False

def vcv_questions():
        
        i_labels = input("Provide input labels: ")
        o_labels = input("Provide output labels: ")
        install = input("Would you like to install the compiled module? y/N: ")
        
    
        
        
        if not install:
                    install = False
        elif install.upper() != "N" or install.upper() != "YES":
            install = False
        return (i_labels, o_labels)
if __name__ == "__main__":
    main()