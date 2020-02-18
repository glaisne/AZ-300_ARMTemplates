# VNet Peering


Allow ping:
 ping peeringserverNew-NetFirewallRule -displayName "Allow ICMPv-In" -protocol ICMPv4

# VPN Gateway

## Point-to-Site VPN Gateway

The 'Point' in this lab is VM1
The 'Site' in this lab is VNET2

1. VNET2: Create a 'gateway subnet' subnet.
2. Create the VPN Gateway (30-45 min.)
  a. Gateway Type: VPN
  b. VPN type: Route-based
  c. SKU: VpnGw1
  d. Virtual Network: VNET2
  e. Public IP address: Create New
  f. Public IP address name: vpnGateway-ip
  g. Public Ip address SKU: Basic
3. VM2: Install IIS
4. VM2: Make the homepage a static page with the name of the host.
5. VM1: Create self-signed (root) certificate
  a. Powershell: 
```powershell
$cert = New-SelfSignedCertificate -type Custom -KeySpec Signature `
    -Subject "CN=P2SRootCert" -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsageProperty Sign -KeyUsage CertSign
```
6. VM1: Create a certificate out of the root certificate
```powershell
New-SelfSignedCertificate -Type Custom -DnsName P2SChildCert -KeySpec Signature `
    -Subject "CN=P2SChildCert" -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Signer $cert -TextExtension @("2.5.29.37={text}1.3.6.1.55.7.3.2")
```
7. VM1: Export the P2SRootCert
    a. Do NOT export the private key
    b. Base-64 encoded X.509 (.CER)
    c. filename: clientcert.cer
8. VM1: Copy the clientcert.cer text (not including the '-----' lines, just the encrypted data)
9. Wait for the VPN Gateway to be created.
10. In the Azure Portal, open the VPN Gateway
11. VPNG: configure Point-to-site configuration
    a. Click the Point-to-site configuration tab
    b. Click on 'Configure now'
    c. In Address pool, enter a CIDR address from which incoming connections will get their 'source' IP address. (20.0.0.0/24)
    d. Tunnel type: IKEv2 and SSTP (SSL)
    e. Root certificates: Name: clientcert
    f. Root certificates: Public Certificate Data: <Paste the certificate data from #8 above>
    g. Click 'Save'
    h. After a few minutes you will be able to click the 'Download VPN client' button.
    i. Download the VPN client and copy it to VM1
12. VM1: install the VPN client (VpnClientSetupAmd64)
13. VM1: Connect to the VPN connection
14. Portal: Copy the private IP address of VM2
15. VM1: Open IE and paste in the private IP address of VM2 in the address bar.

You have just connected via point to site VPN to an Azure Network.

# Endpoint

