"""
An example of Vector Base Amplitude Panning. Inclues a 4 channel speaker array example where speakers are placed at azimuths of -55, 55, -110, and 110 degrees. Also includes a 7-channel surround sound example.

The position of the audio source is controlled by the mouse. The corners of the screen are positioned directly on top of the speakers.
"""

from mmm_python import *
from math import pi
# instantiate and load the graph
mmm_audio = MMMAudio(128, num_output_channels=11, graph_name="VectorBasePanning3D", package_name="examples")


mmm_audio.start_audio()
degrees_to_radians = pi/180

mmm_audio.send_float("az", -0.45 * pi)
mmm_audio.send_float("ht", -0.2 * 2 * pi)
mmm_audio.send_float("az", -0.25  * pi)
# mmm_audio.send_float("az", 0.375 * 2 * pi)
# mmm_audio.send_float("az", 0.5 * 2 * pi)
# mmm_audio.send_float("az", 0.625 * 2 * pi)
# mmm_audio.send_float("az", 0.75 * 2 * pi)
# mmm_audio.send_float("az", 0.875 * 2 * pi)
mmm_audio.send_float("az", 185 * degrees_to_radians + (1.0 * pi))


#Enable/disable mouse
mmm_audio.send_bool("mouse", True)
mmm_audio.send_bool("mouse", False)

# for Wayland use the fake mouse
MMMAudio.fake_mouse()

mmm_audio.stop_audio()

mmm_audio.plot(48000)

# This implementation of VBAP uses the Quickhull algorithm to determine speaker triplets. For further explanantion see this paper by Hongchan Choi: https://repository.gatech.edu/atmire-ds/25e3c444-6cde-4c2b-a4e0-f015cb46211c/page/2
# Executing the code below shows a 3d representation of all speaker triplets.
from math import cos, sin, pi
import numpy as np
from matplotlib import pyplot as plt
from scipy.spatial import ConvexHull
degrees_to_radians = pi/180


# A 7.1.4 Atmos Array 
speaker_positions = [
    
    [0.0, 0],#Center
    [25 * degrees_to_radians, 0],# L
    [-25 * degrees_to_radians, 0],# R
    [90 * degrees_to_radians, 0], # LS
    [-90 * degrees_to_radians, 0], # RS
    [135  * degrees_to_radians, 0], # LB
    [-135 * degrees_to_radians, 0], # RB
    [40 * degrees_to_radians, 35 * degrees_to_radians], #LTF
    [-40 * degrees_to_radians, 35 * degrees_to_radians], #RTF
    [120 * degrees_to_radians, 35 * degrees_to_radians], #LTR
    [-120 * degrees_to_radians, 35 * degrees_to_radians] #RTF

]



speaker_vectors = np.array([[cos(x[0]) * cos(x[1]),sin(x[0]) * cos(x[1]), sin(x[1])] for x in speaker_positions])

# for speaker in speaker_positions:
#   speaker_uvs.append([(sin(speaker[0])) * cos(speaker[1]), sin(speaker[1])])

qhull = ConvexHull(speaker_vectors)
qhull.simplices
triplets = []

for triplet in qhull.simplices:
    if speaker_vectors[triplet[0]][2] == 0.0 and speaker_vectors[triplet[1]][2] == 0.0 and speaker_vectors[triplet[2]][2] == 0:
        pass
    else:
        triplets.append(triplet)

fig = plt.figure()
ax = fig.add_subplot(projection="3d")




xs = [vec[0] for vec in speaker_vectors]
ys = [vec[1] for vec in speaker_vectors]
zs = [vec[2] for vec in speaker_vectors]

ax.scatter(xs,ys,zs) #type:ignore

for i in range(len(triplets)):
    speaker_1 = triplets[i][0]
    speaker_2 = triplets[i][1]
    speaker_3 = triplets[i][2]

    
    ax.plot3D(
        [xs[speaker_1], xs[speaker_2]], 
        [ys[speaker_1], ys[speaker_2]],
        [zs[speaker_1], zs[speaker_2]]
    )

    ax.plot3D(
            [xs[speaker_2], xs[speaker_3]], 
            [ys[speaker_2], ys[speaker_3]],
            [zs[speaker_2], zs[speaker_3]]
        )
    
    ax.plot3D(
            [xs[speaker_1], xs[speaker_3]], 
            [ys[speaker_1], ys[speaker_3]],
            [zs[speaker_1], zs[speaker_3]]
        )

for i in range(len(speaker_vectors)):
    ax.text(xs[i], ys[i], zs[i], "Speaker" + str(i), color='black', fontsize=10)
plt.show()


