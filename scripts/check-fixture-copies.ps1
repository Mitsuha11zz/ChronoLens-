$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$newline = [string][char]10
$cases = @(
    @{ Test = 'solver/fixtures_test.mbt'; Function = 'fixture_four'; Fixture = 'fixtures/four-events.jsonl' },
    @{ Test = 'solver/fixtures_test.mbt'; Function = 'fixture_negative'; Fixture = 'fixtures/negative-cycle.jsonl' },
    @{ Test = 'solver/fixtures_test.mbt'; Function = 'fixture_components'; Fixture = 'fixtures/component-analysis.jsonl' },
    @{ Test = 'constraints/integration_test.mbt'; Function = 'mixed_fixture'; Fixture = 'fixtures/mixed-associations.jsonl' }
)
foreach ($case in $cases) {
    $testPath = Join-Path $projectRoot $case.Test
    $fixturePath = Join-Path $projectRoot $case.Fixture
    $testSource = [IO.File]::ReadAllText($testPath)
    $pattern = '(?s)fn ' + [regex]::Escape($case.Function) + '\(\) -> String \{(?<body>.*?)\r?\n\}'
    $match = [regex]::Match($testSource, $pattern)
    if (-not $match.Success) {
        throw "Missing embedded fixture function: $($case.Function)"
    }
    $embeddedLines = @(
        $match.Groups['body'].Value -split '\r?\n' |
            Where-Object { $_ -match '^\s*#\|' } |
            ForEach-Object { $_ -replace '^\s*#\|', '' }
    )
    $embedded = $embeddedLines -join $newline
    $fixtureBody = ([IO.File]::ReadAllText($fixturePath) -replace '\r\n', $newline).TrimEnd([char[]]@(13, 10))
    if ($embedded -cne $fixtureBody) {
        throw "Embedded test data differs from $($case.Fixture); update the copy deliberately."
    }
    Write-Output "MATCH $($case.Fixture)"
}
