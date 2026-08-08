# -*- coding: utf-8 -*-
"""
QgisStreamMCP Processing-script entry: pdal_las_to_copc
══════════════════════════════════════════════════════════
Convers a raw .las/.laz file to COPC-LAZ via the containerised PDAL.
Discovered by QGIS because it lives in the user profile's
processing/scripts/ directory; labelled "PDAL > LAS to COPC" in the Toolbox.

srs_epsg is REQUIRED because CZMIL LAS files ship with an empty
comp_spatialreference — see README/CLAUDE.md.
"""

from qgis.core import (
    QgsProcessing,
    QgsProcessingAlgorithm,
    QgsProcessingParameterFile,
    QgsProcessingParameterString,
    QgsProcessingParameterFileDestination,
)

import sys
sys.path.insert(0, '/app')

from helpers.pdal_copc import las_to_copc


class PdalLasToCopc(QgsProcessingAlgorithm):

    INPUT = 'INPUT'
    SRS = 'SRS'
    OUTPUT = 'OUTPUT'

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterFile(
                self.INPUT,
                'Input LAS/LAZ file',
                extension='las'))
        self.addParameter(
            QgsProcessingParameterString(
                self.SRS,
                'EPSG SRS auth string (e.g. EPSG:26918)',
                defaultValue='EPSG:26918'))
        self.addParameter(
            QgsProcessingParameterFileDestination(
                self.OUTPUT,
                'Output COPC-LAZ file',
                fileFilter='COPC-LAZ (*.copc.laz *.laz)'))

    def processAlgorithm(self, parameters, context, feedback):
        in_path = self.parameterAsString(parameters, self.INPUT, context)
        srs = self.parameterAsString(parameters, self.SRS, context) or ''
        out_path = self.parameterAsFileOutput(parameters, self.OUTPUT, context)
        if not srs:
            raise ValueError(
                'SRS parameter is required. Pass EPSG:XXXX (e.g. EPSG:26918 for CZMIL/UTM 18N).')

        feedback.pushInfo(f'pdal_las_to_copc: {in_path} -> {out_path} (srs={srs})')
        res = las_to_copc(in_path, out_path, srs_epsg=srs, timeout=600)
        feedback.pushInfo(f'pdal_las_to_copc result: {res}')
        if not res.get('success'):
            raise Exception(res.get('error', 'pdal_las_to_copc failed'))
        return {self.OUTPUT: res['output_path'], 'SIZE': res['output_size']}

    def name(self):
        return 'pdal_las_to_copc'

    def displayName(self):
        return 'PDAL: LAS → COPC'

    def group(self):
        return 'PDAL'

    def groupId(self):
        return 'pdal'

    def shortHelpString(self):
        return ('Converts raw .las/.laz to cloud-optimised COPC-LAZ using '
                'the containerised PDAL. Use the result as a Copc layer in QGIS.')

    def createInstance(self):
        return PdalLasToCopc()


# Register the algorithm with the Processing provider at import time so that
# QGIS picks it up the moment this file lands in processing/scripts/.
