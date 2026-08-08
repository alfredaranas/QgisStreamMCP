"""
QgisStreamMCP Processing-script entry: galaxy_class_histogram
══════════════════════════════════════════════════════════════════
Post-classification stats for a COPC: returns a {class: count} histogram
using `pdal filters.groupby`. Used as the second stage of the
galaxy_water_classify model3 (B9): after the model writes
/data/jobs/galaxy_water_classify.copc.laz, this script emits a JSON file
/data/jobs/galaxy_water_classify.hist.json with the histogram, which the
model then renders to PNG via QGIS's plotter algorithm.
"""

from qgis.core import (
    QgsProcessingAlgorithm,
    QgsProcessingParameterFile,
    QgsProcessingParameterFileDestination,
    QgsProcessingParameterString,
)

import json
import sys
sys.path.insert(0, '/app')

from helpers.pdal_copc import class_histogram


class GalaxyClassHistogram(QgsProcessingAlgorithm):

    INPUT = 'INPUT'
    DIM = 'DIM'
    OUTPUT = 'OUTPUT'

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterFile(
                self.INPUT,
                'Classified point cloud (LAS/LAZ/COPC)',
                extension='las'))
        self.addParameter(
            QgsProcessingParameterString(
                self.DIM,
                'PDAL dimension to histogram',
                defaultValue='Classification'))
        self.addParameter(
            QgsProcessingParameterFileDestination(
                self.OUTPUT,
                'Output histogram JSON',
                fileFilter='JSON (*.json)'))

    def processAlgorithm(self, parameters, context, feedback):
        in_path = self.parameterAsString(parameters, self.INPUT, context)
        dim = self.parameterAsString(parameters, self.DIM, context) or 'Classification'
        out_path = self.parameterAsFileOutput(parameters, self.OUTPUT, context)
        feedback.pushInfo(f'galaxy_class_histogram: {in_path} dim={dim}')
        hist = class_histogram(in_path, dim=dim, timeout=300)
        with open(out_path, 'w', encoding='utf-8') as f:
            json.dump(hist, f, indent=2)
        feedback.pushInfo(f'galaxy_class_histogram wrote {len(hist)} bins to {out_path}')
        return {self.OUTPUT: out_path}

    def name(self):
        return 'galaxy_class_histogram'

    def displayName(self):
        return 'Galaxy: Classification Histogram (JSON)'

    def group(self):
        return 'Galaxy'

    def groupId(self):
        return 'galaxy'

    def shortHelpString(self):
        return ('Runs `pdal filters.groupby` and emits a JSON histogram '
                '{value: count} for the requested dimension (default Classification).')

    def createInstance(self):
        return GalaxyClassHistogram()


