from mmm_python import *
m_a = MMMAudio(128, graph_name="TestFlangerPhaser", package_name="examples.tests")
m_a.start_audio() 

m_a.send_int("which_source", 1) # 0 for sample, 1 for noise
m_a.send_float("which_fx", 0) # 0 for phaser, 1 for flanger
m_a.send_float("center_freq", 500.)
m_a.send_float("Q", 0.5) # phaser only
m_a.send_float("feedback_coef", 0.7) # flanger only
m_a.send_float("lfo_freq", 0.1)
m_a.send_float("lfo_octaves", 3)
m_a.send_float("freq_offset", 0.1)
m_a.send_float("mix", 0.5)