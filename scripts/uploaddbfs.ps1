param([String]$type)

if ($ENV:debug_log) {
    Start-Transcript -Path "./upload.dbfs.$type.log"
}

$uploadFolder = $env:upload_folder
$uploadDest = $env:upload_dest

function Test-UploadFolder($path) {
    if (Test-Path $path -PathType Container) {
        return
    }

    throw "upload_dest=$path must be a valid folder on the local machine"
}


function create {
    Write-Host  "Starting create"

    # Create a list of what we uploaded to track in state 
    $items = Get-ChildItem $uploadFolder | Select-Object -ExpandProperty Name

    # This is idempotent (at the moment) so ok to rerun even if dir already exists
    databricks fs mkdirs "dbfs:/$uploadDest"

    $createResult = databricks fs cp -r $uploadFolder "dbfs:/$uploadDest"
    
    Test-ForDatabricksFSError $createResult
    
    # Write json to stdout for provider to pickup and store state in terraform 
    # importantly this allows us to track the `cluster_id` property for future read/update/delete ops
    $itemsState = @{ files = $items } | ConvertTo-Json
    
    Write-Host  $itemsState
}

function read {
    Write-Host  "Starting read"

    # Get the current status of the cluster
    $itemsInClusterRaw = databricks fs ls "dbfs:/$uploadDest/"
    Test-ForDatabricksFSError $itemsInClusterRaw

    $itemsInCluster = $itemsInClusterRaw.Split([Environment]::NewLine)
    
    # Output just the cluster ID to workaround an issue with complex objects https://github.com/scottwinkler/terraform-provider-shell/issues/32
    @{ files = $itemsInCluster } | ConvertTo-Json | Write-Host 
}

function update {
    Write-Host  "Starting update"
    # WARNING: This will remove everything in the dest including the folder
    # and reupload all files. In future this can be updated to be more targetted
    delete
    create
}

function delete {
    Write-Host  "Starting delete"


    #WARNING: This will remove the whole destination folder!
    # Ensure that this is only used for asset upload from terraform and not 
    # used to also store data or update the script to only delete named files.
    $itemsInClusterRaw = databricks fs rm -r "dbfs:/$uploadDest"
    Test-ForDatabricksFSError $itemsInClusterRaw
    
    # Empty state update
    Write-Host  "{}"
}

function Test-ForDatabricksFSError($response) {
    # Todo - maybe improve
    # Currently CLI returns, for example::
    # - Error: The local file ./doesntexist does not exist.
    # - Error: b'{"error_code":"RESOURCE_ALREADY_EXISTS","message":"A file or directory already exists at the input path dbfs:/doesntexist/really/sure."}'
    if ($response -like "Error: *") {
        Write-Host  "CLI Response: $response"
        Throw "Failed to execute Databricks CLI. Error response."
    }
}

Switch ($type) {
    "create" { create }
    "read" { read }
    "update" { update }
    "delete" { delete }
}