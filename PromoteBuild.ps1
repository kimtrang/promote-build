param(
    [Parameter(Mandatory=$true)][string]$InVersion,
    [Parameter(Mandatory=$true)][string]$OutVersion,
    [string]$ReleaseNotes,
    [string]$NugetApiKey,
    [switch]$Push,
    [switch]$Download,
    [switch]$Prerelease
)

function Take-While() {
    param( [scriptblock]$pred = $(throw "Need a predicate") )
    begin {
        $take = $true
    } process {
        if($take) {
            $take = & $pred $_
            if($take) {
                $_
            }
        } else {
            return
        }
    }
    
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$ErrorActionPreference = "Stop"

if($ReleaseNotes) {
    $ReleaseNotes = Resolve-Path -Path $ReleaseNotes
}

if($Download) {
    Remove-Item -Force *.nupkg -ErrorAction Ignore
    $package_names = "Couchbase.Lite","Couchbase.Lite.Support.UWP","Couchbase.Lite.Support.NetDesktop","Couchbase.Lite.Support.Android","Couchbase.Lite.Support.iOS","Couchbase.Lite.Enterprise","Couchbase.Lite.Enterprise.Support.UWP","Couchbase.Lite.Enterprise.Support.NetDesktop"
    foreach($package in $package_names) {
        Write-Host "Downloading http://mobile.nuget.couchbase.com/nuget/Internal/package/$package/$InVersion..."
        Invoke-WebRequest http://mobile.nuget.couchbase.com/nuget/Internal/package/$package/$InVersion -Out "${package}.${InVersion}.nupkg"
    }
}

foreach($file in (Get-ChildItem $pwd -Filter *.nupkg)) {
    $packageComponents = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).Split('.') | Take-While { -Not [System.Char]::IsDigit($args[0][0]) }
    $package = [System.String]::Join(".", $packageComponents)
    Remove-Item -Recurse -Force $package -ErrorAction Ignore
    New-Item -ItemType Directory $package
    [System.IO.Compression.ZipFile]::ExtractToDirectory("${package}.${InVersion}.nupkg", $package)
    Push-Location $package
    [xml]$nuspec = Get-Content -Path "${package}.nuspec"
    $nuspec.package.metadata.version = $OutVersion
    if($ReleaseNotes) {
        $nuspec.package.metadata.releaseNotes = $(Get-Content $ReleaseNotes) -join "`r`n"
    }

    $nuspec.Save([System.IO.Path]::Combine($pwd, "${package}.nuspec"))
    Pop-Location

    Remove-Item -Path "$package.$OutVersion.nupkg" -ErrorAction Ignore -Force
    [System.IO.Compression.ZipFile]::CreateFromDirectory($package, "$package.$OutVersion.nupkg")
    Remove-Item -Recurse -Force -Path $package
    Remove-Item -Force -Path "${package}.${InVersion}.nupkg"
}

if($Push) {
    if(![System.IO.File]::Exists("nuget.exe")) {
        Invoke-WebRequest https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile nuget.exe
    }

    foreach($file in (Get-ChildItem $pwd -Filter *.nupkg)) {
        if($Prerelease) {
            $NugetUrl = "http://mobile.nuget.couchbase.com/nuget/Developer"
        } else {
            $NugetUrl = "https://api.nuget.org/v3/index.json"
        }

        & nuget.exe push $file -ApiKey $NugetApiKey -Source $NugetUrl
    }
}