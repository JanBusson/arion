## ADDED Requirements

### Requirement: Music-first external discovery mode selection
The client SHALL display two mutually exclusive external-discovery controls, `Music` and `All`, beside the library search control. `Music` SHALL be selected when the client starts and the selected mode SHALL remain active for subsequent searches during that client session unless the owner changes it. The selector SHALL affect only explicit external discovery and SHALL NOT filter the local catalog, contact an external provider while typing, or start discovery merely because the selection changed.

#### Scenario: Start with music selected
- **WHEN** the owner starts the client and submits a local catalog search
- **THEN** `Music` is selected while the local catalog request remains an ordinary unfiltered-by-mode search

#### Scenario: Choose broad discovery
- **WHEN** the owner selects `All` and explicitly starts external discovery after an empty local result
- **THEN** the client requests `all` discovery for the latest submitted query

#### Scenario: Change mode without searching
- **WHEN** the owner changes between `Music` and `All`
- **THEN** the client makes no external request until the owner activates the discovery action

### Requirement: Mode-consistent candidate review
The client SHALL label the explicit discovery action for the selected mode, send that mode in the candidate request, and display only candidates returned for the current query and mode. Changing the mode after candidates have loaded SHALL clear those candidates and require another explicit discovery action. Music candidates SHALL present their artist display text as the creator identity while retaining the existing title, duration, thumbnail, canonical-page review, selection, and authorization controls.

#### Scenario: Review music candidates
- **WHEN** `Music` discovery returns song candidates
- **THEN** the client identifies the action and result state as music discovery and shows each song title and artist without preselecting a candidate

#### Scenario: Switch away from displayed candidates
- **WHEN** candidates are visible and the owner changes the discovery mode
- **THEN** the client removes the old-mode candidates and does not search the newly selected mode automatically

#### Scenario: Fit the selector on supported layouts
- **WHEN** the mode selector is shown on a narrow Android layout or a wider browser layout
- **THEN** both choices and the search control remain readable and operable without horizontal overflow
