import json
import numpy as np
from matplotlib import pyplot as plt
from scipy.spatial import ConvexHull
from math import cos, sin, pi


class SpeakerHelper:
    
    def __init__(self):
        """
        Save, Load, and Visualize speaker arrays.
        """
        
        pass
    
    @staticmethod
    def save_array(array: list, path : str, to_radians : bool = False):
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
        
        
    @staticmethod
    def load_array(path : str) -> list:
        """
        Load a list of speaker azimuths from a JSON file. 
        
        Args:
            path: The path to the JSON file to load.
        """
        
        speaker_array = []
        
        with open(path, "r") as file:
            loaded_dict = json.load(file)
        
        for key in loaded_dict:
            speaker_array.append(loaded_dict[key])
        
        return speaker_array

    @staticmethod
    def show_vbap3d_array(array, az_in_radians = True):
        """
        Displays a visualization of the speaker triplets for a 3D VBAP array using matplotlib. 
        """
        
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

    @staticmethod
    def generate_circular_array(num_speakers : int, offset: float = 0.0, from_degrees: bool = False, as_pairs: bool = False, filename : None | str = None) -> list:
        """
        Formats equidistant speaker positions in a circular array for a given number of speakers. By default, returns azimuth positions in a clockwize sequence.
        
        Args:
            num_speakers: The number of speakers in the array.
            offset: An offset angle for the array.
            from_degrees: If True, will convert the incoming offset from degrees into radians.
            as_pairs: If True, will map the speakers in pairs instead of a clockwize sequence.
            filename: An optional file name to save the generated array to.
            
        Returns:
            A list of speaker azimuths in radians.
        """
        
        step = pi/num_speakers
        out = []
        
        if from_degrees:
            offset = offset * (180/pi)
        
        if as_pairs:
           for i in range(int(num_speakers/2)):
                out.append(-1 * (step * (1 + (i * 2)) + offset))
                out.append(step * (1 + (i * 2)) + offset)
                
        else:
            for i in range(num_speakers):
                out.append(step * (1 + (i * 2)) + offset)
            
        
        if filename:
            SpeakerHelper.save_array(out, filename)
        
        return out