import json
import numpy as np
from matplotlib import pyplot as plt
from scipy.spatial import ConvexHull
from math import cos, sin, pi


class SpeakerHelper:
    
    def __init__(self):
        
        pass
    
    @classmethod
    def save_array(cls, array: list, path : str, to_radians : bool = False):
        """
        Saves an array of speaker positions in azimuths as a JSON file.
        Arugments:
            array: A list, or list of lists/tuples, of azimuth values for speaker positions.
            path: The path to save the array to. 
        """
        speaker_array = {}
        
        
        for i, speaker in enumerate(array):
            if to_radians:
                speaker[0] *= pi/180
                if len(speaker) > 1:
                    speaker[1] *= pi/180
                    
            speaker_array[str(i)] = speaker
        
        with open(path, "w") as file:
            json.dump(speaker_array, file, indent=4)
        
        
    @classmethod
    def load_array(cls, path : str) -> list:
        speaker_array = []
        
        with open(path, "r") as file:
            loaded_dict = json.load(file)
        
        for key in loaded_dict:
            speaker_array.append(loaded_dict[key])
        
        return speaker_array

    @classmethod
    def show_vbap3d_array(cls, array, az_in_radians = True):
        
        if not az_in_radians:
            for speaker in array:
                speaker[0] *= pi/180
                speaker[1] *= pi/180
            

        speaker_vectors = np.array([[cos(x[0]) * cos(x[1]),sin(x[0]) * cos(x[1]), sin(x[1])] for x in array])

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

