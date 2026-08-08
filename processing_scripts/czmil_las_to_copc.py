"""
QgisStreamMCP Processing-script entry: czmil_las_to_copc
══════════════════════════════════════════════════════════
CZMIL-tuned wrapper around pdal_las_to_copc:
 - Always assumes EPSG:26918 (NAD83 / UTM 18N, NCMP / NC coast)
 - Rejects inputs that look like a COPC already (idempotent: if input ends
   in .copc.laz and a_srs is set in metadata, just symlinks)
"""

from qgis.core import (
    QgsProcessingAlgorithm,
    QgsProcessingParameterFile,
    QgsProcessingParameterFileDestination,
)

import sys
sys.path.insert(0, '/app')

from helpers.pdal_copc import las_to_copc


class CzmilLasToCopc(QgsProcessingAlgorithm):

    INPUT = 'INPUT'
    OUTPUT = 'OUTPUT'

    def initAlgorithm(self, config=None):
        self.addParameter(
            QgsProcessingParameterFile(
                self.INPUT,
                'Input CZMIL LAS/LAZ file',
                extension='las'))
        self.addParameter(
            QgsProcessingParameterFileDestination(
                self.OUTPUT,
                'Output COPC-LAZ file',
                fileFilter='COPC-LAZ (*.copc.laz *.laz)'))

    def processAlgorithm(self, parameters, context, feedback):
        in_path = self.parameterAsString(parameters, self.INPUT, context)
        out_path = self.parameterAsFileOutput(parameters, self.OUTPUT, context)
        feedback.pushInfo(f'czmil_las_to_copc: {in_path} -> {out_path} (srs=EPSG:26918)')
        res = las_to_copc(in_path, out_path, srs_epsg='EPSG:26918', timeout=900)
        feedback.pushInfo(f'czmil_las_to_copc result: {res}')
        if not res.get('success'):
            raise Exception(res.get('error', 'czmil_las_to_copc failed'))
        return {self.OUTPUT: res['output_path'], 'SIZE': res['output_size']}

    def name(self):
        return 'czmil_las_to_copc'

    def displayName(self):
        return 'CZMIL: LAS → COPC (UTM 18N)'

    def group(self):
        return 'CZMIL'

    def groupId(self):
        return 'czmil'

    def shortHelpString(self):
        return ('CZMIL-specific wrapper: always assigns EPSG:26918 (NAD83 / UTM 18N). '
                'For other zones use "PDAL > LAS → COPC" directly.')

    def createInstance(self):
        return CzmilLasToCopc()


