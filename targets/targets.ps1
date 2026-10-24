# Registro de clientes soportados.
# Unico lugar del codigo donde aparecen nombres de cliente: el motor (install.ps1) solo
# conoce dos tipos, 'json-config' y 'pointer'. Anadir un cliente = anadir una entrada aqui
# y su plantilla en templates/targets/.
#
# - json-config : el cliente lee su configuracion de un JSON propio (se fusiona, no se pisa).
# - pointer     : el cliente lee un archivo propio; el Harness escribe un puntero corto que
#                 remite a harness/AGENTS.md (fuente unica; nunca se duplica el contenido).

function Get-HarnessTargets {
    @(
        [pscustomobject]@{
            Name             = 'opencode'
            Kind             = 'json-config'
            ConfigFile       = 'opencode.json'
            Template         = 'opencode.json'
            TemplateSkillsOnly = 'opencode.skills-only.json'
            InstructionsValue = 'harness/AGENTS.md'
        },
        [pscustomobject]@{
            Name        = 'codex'
            Kind        = 'pointer'
            PointerFile = 'AGENTS.md'
            Template    = 'targets/codex-AGENTS.md'
            InstructionsValue = 'harness/AGENTS.md'
        },
        [pscustomobject]@{
            Name        = 'cursor'
            Kind        = 'pointer'
            PointerFile = '.cursor/rules/harness.mdc'
            Template    = 'targets/cursor-harness.mdc'
            InstructionsValue = 'harness/AGENTS.md'
        },
        [pscustomobject]@{
            Name        = 'cline'
            Kind        = 'pointer'
            PointerFile = '.clinerules/harness.md'
            Template    = 'targets/cline-harness.md'
            InstructionsValue = 'harness/AGENTS.md'
        }
    )
}
