# OpenVAS GVM Vulnerability Scanner Install Scripts

#### 📦 **SOURCE build auto setup link**
```shell
wget https://raw.githubusercontent.com/itiligent/Greenbone-OpenVAS-Install/main/gvm-build-from-source.sh && chmod +x gvm-build-from-source.sh && ./gvm-build-from-source.sh
```

#### 🐳 **DOCKER build auto setup link** 
```shell
wget https://raw.githubusercontent.com/itiligent/Greenbone-OpenVAS-Install/main/gvm-build-docker.sh && chmod +x gvm-build-docker.sh && ./gvm-build-docker.sh
```

*Note: The Official GVM Docker containers should be considered experimental as there does not seem to be much QA of container updates. **For stable production use, the source build is recommended.***

### 📋 **Prerequisites**

- Ubuntu 22.04 LTS / Debian 12 or 11 / Raspbian Bullseye
- Minimum 8GB RAM and 80GB HDD
- Private DNS entries matching the server IP address (required for TLS)
- Email relay permitted from the scanner appliance's IP address
- An O365 (or similar service) email-enabled account with an app password configured
- The user executing the wget installer script **must be a member of the sudo group** 🛡️

### 📧 **Configuring email reporting**

Both build options install Postfix for sending of scan reports to email. (Normally a GVM Pro option)

 - For the the source build option, simply run `add-smtp-relay-o365.sh`
 - With the Docker option, Greenbone's container updates will occasionally overwrite the Postfix install. The update script will automatically check and re-add Postfix, but your SMTP config must be re-added. You can modify `add-docker-smtp-relay-0365.sh` to automatically re-insate your SMTP config and automate this via the $DOWNLOAD_DIR/update-gvm.sh update script. 

###  ⬆️ **Upgrading and updating the scanner** 
 - **Source Builds:** CVE feed updates are scheduled by the installer daily at a random time. To upgrade the scanner application run `gvm-build-from-source-upgrader.sh`. 
 - **Docker builds:** As CVE feed updates are bundled as container updates, the included `update-gvm.sh` is set to automatically pull containers weekly. (Daily container updates greatly increase the likelihood of breakage.)

### 🔒 **SSL Note**

For both build options, an Nginx reverse proxy is installed and browser certificates are also created locally ($site.crt, $site.key & $site.pfx). Instructions for importing these into client systems to avoid browser TLS error messages is provided on screen when the script completes.

### 💻 **Performing vulnerability scans with Windows SMB authentication**

If you wish to perform scans with Windows SMB authentication, follow these steps:

1. Run the included PowerShell script `prep-windows-gvm-cred-scan.ps1` on all Windows hosts to be scanned with SMB credentials.
2. Create a GVM service account on all Windows hosts to be scanned, adding it to the local Administrators group (this service account must NOT be a built-in Windows account).
3. Create a new credentials object in the GVM management console reflecting the new Windows service account.
4. Create a scan target, add Windows devices to scan, and select the new credentials object for this target.
5. Create a new scan task for the credentialed scan target from step 4, then run or schedule the scan task.

