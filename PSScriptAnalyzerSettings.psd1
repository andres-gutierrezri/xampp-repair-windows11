@{
    # Exclusiones deliberadas:
    #  - PSAvoidUsingWriteHost: los scripts son interactivos y muestran progreso en consola.
    #  - PSAvoidUsingEmptyCatchBlock: los sondeos de puerto/cierre ignoran fallos esperados.
    #  - PSUseSingularNouns: los nombres de funciones internas siguen el español del proyecto.
    #  - PSReviewUnusedParameter: los conmutadores se leen desde funciones hijas (ámbito dinámico).
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseSingularNouns',
        'PSReviewUnusedParameter',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseShouldProcessForStateChangingFunctions'
    )
    Severity     = @('Error', 'Warning')
}
