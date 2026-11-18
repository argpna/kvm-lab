# Runs once at the first logon of a new VM (started by unattend.xml). Log: first-logon.log next to this file.
$ErrorActionPreference = 'Stop'
Start-Transcript -Path C:\Windows\Setup\Scripts\first-logon.log -Force

# The image build only copies the virtio drivers; install them so the NIC gets netkvm.
pnputil.exe /add-driver C:\Windows\Drivers\VirtIO\*.inf /install | Out-Host
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

Enable-PSRemoting -SkipNetworkProfileCheck -Force
# Local admins other than the built-in Administrator are denied over WinRM without this.
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Enable-WSManCredSSP -Role Server -Force | Out-Null

# PowerShell 7 (the MSI was copied in by the image build), registered as a remoting endpoint.
$msi = 'C:\Windows\Setup\Scripts\pwsh.msi'
$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$msi`" /qn /norestart ADD_PATH=1 REGISTER_MANIFEST=1 ENABLE_PSREMOTING=1 USE_MU=0 ENABLE_MU=0 DISABLE_TELEMETRY=1"
if ($p.ExitCode -notin 0, 3010) { throw "pwsh.msi failed with exit code $($p.ExitCode)" }
Remove-Item $msi -Force

Get-NetAdapter | Format-Table -AutoSize | Out-String | Write-Host

# Open 5986 last: the lab treats an open port as "ready".
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(10)
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } | Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null
New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow | Out-Null
Stop-Transcript
