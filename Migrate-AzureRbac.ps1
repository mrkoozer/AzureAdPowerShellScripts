# USAGE Scenarios

# Export-MyAzureRmRoleAssignment
# > Will export RBAC for all subscriptions user has access to
#   > Each Subscription will have a seperate CSV file 
#     > Subscription--{Subscription Name}.csv
#   > There will also be a single CSV file with all RBAC permissions 
#     > Subscription--All-Roles.csv
#   > Group Members will also be exported to a CSV file 
#     > GroupMembers--{Group Name}.csv

# Import-MyAzureRmRoleAssignment -CsvFile {File Name} -SubId {Subscription Id}
# > Will import RBAC permissions from the specified file and to the specified subscription ID
# > Example: Import-MyAzureRmRoleAssignment -CsvFile 'Subscription--All-Roles.csv' -SubId '43a5488c-9de6-42e5-abde-3cb34e8f0edc'


# Install required PowerShell modules if not already installed
#  Troubleshooting: If on Windows 10+
#   > Install the latest version of WMF 
#   > https://www.microsoft.com/en-us/download/details.aspx?id=54616
#   > Then run 'Install-Module PowerShellGet -Force'
#  Troubleshooting: If on Windows previous to 10
#   > Install PackageManagement modules
#   > http://go.microsoft.com/fwlink/?LinkID=746217
#   > Then run 'Install-Module PowerShellGet -Force'

# Check if AzureAD and AzureRM PowerShell modules are installed
If ( (Get-Module -ListAvailable | where {$_.Name -match "AzureAD"}).Count -eq 0 ) { Install-Module AzureAD -scope CurrentUser }
If ( (Get-Module -ListAvailable | where {$_.Name -match "AzureRM.Resources"}).Count -eq 0 ) { Install-Module AzureRM -scope CurrentUser}

# Connect to AzureAD and AzureRM PowerShell services
if (!$SignedIn) {
  try {
    write-output "Connecting to Azure Resource Manager"
    Login-AzureRmAccount
    write-output "Connecting to Azure Active Directory"
    Connect-AzureAD
    $SignedIn = $true
  }
  catch {
    $SignedIn = $false
  }
}


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Export Role Assignments for all subscription logged on user (from Login-AzureRm) has access to
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
function Export-MyAzureRmRoleAssignment {

    $RoleAssignments = @()
    #Traverse through each Azure subscription user has access to
    $subs = Get-AzureRmSubscription
    Foreach ($sub in $subs) {
        $SubName = $sub.Name
        if ($sub.Name -ne "Access to Azure Active Directory") { # You can't assign roles in Access to Azure Active Directory subscriptions
            Set-AzureRmContext -SubscriptionId $sub.id
            Write-Host "Collecting RBAC Definitions for $subname"
            Write-Host ""
            Try {
                $Current = Get-AzureRmRoleAssignment -includeclassicadministrators
                $RoleAssignments += $Current
            } 
            Catch {
                Write-Output "Failed to collect RBAC permissions for $subname"
            }
            
            #Custom Roles do not display their Name in these results. We are forcing this behavior for improved reporting
            Foreach ($role in $RoleAssignments) {
              $ObjectId = $role.ObjectId
              $DisplayName = $role.DisplayName
              If ($role.RoleDefinitionName -eq $null) {
                $role.RoleDefinitionName = (Get-AzureRmRoleDefinition -Id $role.RoleDefinitionId).Name
              }
              if ($role.ObjectType -eq "Group" -and !(Test-Path -path "GroupMembers--$DisplayName.csv")) {
                $Members = Get-AzureADGroupMember -ObjectId $ObjectId
                $Members | Export-CSV ".\GroupMembers--$DisplayName.csv"
              }
            }
            #Export the Role Assignments to a CSV file labeled by the subscription name
            $Current | Export-CSV ".\Subscription--$SubName-Roles.csv"
        }
    }

    #Export All Role Assignments in to a single CSV file
    $RoleAssignments | Export-CSV ".\Subscription--All-Roles.csv"

    # HTML report
    $a = "<style>"
    $a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;font-family:arial}"
    $a = $a + "TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;}"
    $a = $a + "TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;}"
    $a = $a + "</style>"
    $RoleAssignments | ConvertTo-Html -Head $a| Out-file “.\Subscription--All-Roles.html"
}

$role  = ""
$roles = ""
$ImportCsv = ""


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Import Role Assignments from specified CSV file and specify which Subscription to import to
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
function Import-MyAzureRmRoleAssignment {
# Ensure you are signed in to AzureRm (Login-AzureRm)
# Ensure you are signed in to AzureAD (Connect-AzureAD)

# $ImportCSV : Location of CSV file for role assignments
# $SubId : Azure subscription ID to re-apply permissions to
  param (
    [string]$ImportCsv, [string]$SubId
  )

  
  # Make the param -ImportCsv required and import the CSV
  # This is assuming the CSV was exported from Get-AzureRmRoleAssignment
  if(-not($ImportCsv)) { Throw "You must supply a value for -ImportCsv" }
  if(-not($SubId)) { Throw "You must supply a value for -SubId" }

  $HaveAccess = 0
  try {
    Set-AzureRmContext -Subscription $SubId
    $HaveAccess = $True
  } Catch {
    $HaveAccess = $False
    Write-Host "$SubId does not exist or You don't have access to it" -ForegroundColor Red
  }

  If ($HaveAccess) {
      $roles = Import-CSV $ImportCsv
  
      # Start assigning roles
      foreach ($role in $roles) {
        write-host "--- STARTING NEW ROLE ASSIGNMENT ---"
        $RoleDisplayName = $role.DisplayName
        $RoleObjectId = $role.ObjectId
        $RoleScope = $role.scope
        $RoleSignInName = $role.SignInName
        $RoleDefId = $role.RoleDefinitionId
        if ($role.Scope -ne "/") { # Skip Azure AD scope assignments as it is not possible to assign to this scope
      
          # Group Role Assignment
          if ($role.ObjectType -eq "Group") {
            $group = Get-AzureRmAdGroup -SearchString $role.DisplayName
            if ($group.count -eq 1) {
              $GroupId = $group.id
              write-host "New-AzureRmRoleAssignment -scope $rolescope -ObjectId $GroupId -RoleDefinitionId $RoleDefId -verbose"
              New-AzureRmRoleAssignment -scope $rolescope -ObjectId $GroupId -RoleDefinitionId $RoleDefId -verbose
            } 
            elseif ($group.count -gt 1) { 
              write-Host "Could not assign Access Control to Group $roleDisplayName" -ForegroundColor Yellow
              write-Host "Multiple groups exist with the same DisplayName; unable to identify which group to assign Access Control" -ForegroundColor Yellow
            } 
            else { 
              write-Host "Could not assign Access Control to Group $roleDisplayName" -ForegroundColor Yellow
              write-Host "No groups exist with that name" -ForegroundColor Yellow
            }
          } 

          # User Role Assignment
          elseif ($role.ObjectType -eq "User") {
            $InitialDomain = (Get-AzureADDomain | where {$_.IsInitial -eq $true}).Name
            $us = $false # User us external and SignInName has underscore to be replaced by @
        
            #Modify SignInName if external user
            $i = $role.SignInName.indexOf("#EXT#")
            if ($i -eq -1) { $i = $role.SignInName.length }
            else {
              $us = $true
            }
            $role.SignInName = $role.SignInName.Substring(0,$i)

            if ($us -eq $true) {
              $ati = $role.SignInName.lastindexOf("_")
              $part1 = $role.SignInName.Substring(0,$ati)
              $part2 = $role.SignInName.Substring(($ati+1))
              $role.SignInName = $part1 + "@" + $part2
            }

            # Look for UPN suffix
            $ati = $role.SignInName.indexOf("@")
            $suffix = $role.SignInName.Substring(($ati+1))

            # Check if user domain is verified, If not then this user is still external user
            $DomainExists = (Get-AzureAdDomain | where {$suffix -match $_.Name}).Count
            if (!$DomainExists) {
                $role.SignInName = $role.SignInName.Replace("@","_")
                $role.SignInName = $role.SignInName + "#EXT#@" + $InitialDomain
            }

            $SignInName = $role.SignInName
            $user = Get-AzureRmADUser -UserPrincipalName $role.SignInName
            $UserObjectId = $user.Id

            if ($role.RoleDisplayName -eq "CoAdministrator") {
              $rolescope = "/subscriptions/$subid"
              $RoleDefId = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
            }

            if ($user.count -eq 1) {
              write-host "New-AzureRmRoleAssignment -scope $rolescope -ObjectId $userObjectId -RoleDefinitionId $RoleDefId -verbose"
              New-AzureRmRoleAssignment -scope $rolescope -ObjectId $userObjectId -RoleDefinitionId $RoleDefId -verbose
            } elseif ($user.count -eq 0) {
              write-Host "Could not assign Access Control to User $roleSignInName" -ForegroundColor Yellow
              write-Host "User does not exist or can not be found!"  -ForegroundColor Yellow
            }
          } elseif ($role.ObjectType -match "ServicePrincipal") {
              write-host "You will have to manually apply RBAC for service principals: ObjectId: $RoleObjectId" -ForegroundColor Yellow
          } 
        } else { write-host "Assigning to scope '/' level not allowed" -ForegroundColor Yellow}
      }
  }
}


# Export Custom Role Definitions for all subscriptions logged on user (from Login-AzureRm) has access to
function Export-MyAzureRmRoleDefinition {
  $RoleDefinitions = @()
  Foreach ($sub in Get-AzureRmSubscription) {
        if ($sub.Name -ne "Access to Azure Active Directory") {
            Set-AzureRmContext -SubscriptionId $sub.id
            $subname = $sub.name
            Write-Output "Collecting RBAC Definitions for $subname"
            Try {
                #$subname = Get-AzureRmSubscription -SubscriptionId $sub.id | Select Name
                $RoleDefinitions += Get-AzureRmRoleDefinition | Select-Object -Property *

                $roledef = ""
                Write-Output ""
                Foreach ($roledef in (Get-AzureRmRoleDefinition | where{$_.isCustom -eq $true})) {
                    $roledefname = $roledef.Name
                    Get-AzureRmRoleDefinition -Id $roledef.id | Select-Object -Property * | ConvertTo-Json >> "$roledefname.json"
                    Write-Host "Exported Custom Role: $roledefname" -foregroundcolor "yellow"
                }
                Write-Output ""

                if ($roledef -eq "") {
                  Write-Host "There are no custom roles for Subscription: $subname" -foregroundcolor "yellow"
                }
            } 
            Catch {
                Write-Output "Failed to collect RBAC Definitions for $subname"
            }
        }
  }
}

