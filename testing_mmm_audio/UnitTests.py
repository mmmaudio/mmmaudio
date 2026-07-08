from mmm_python import *

def test_control_spec():
    spec = ControlSpec(20.0, 20000.0, 5)
    assert spec.unnormalize(0.5) < 1000
    assert spec.normalize(10000) > 0.75

if __name__ == "__main__":
    test_control_spec()