# Greenbone Vulnerability Manager Install Script
### Source or Docker build options with SSL Nginx reverse proxy & GVM pro email reports

### **GVM build from source auto setup link**
	wget https://raw.githubusercontent.com/itiligent/GVM-Install/main/gvm-build-from-source.sh && chmod +x gvm-build-from-source.sh  && ./gvm-build-from-source.sh 

### **GVM build on Docker auto setup link**
	wget https://raw.githubusercontent.com/itiligent/GVM-Install/main/gvm-build-docker.sh && chmod +x gvm-build-docker.sh && ./gvm-build-docker.sh

### **Prerequisites:**

- Ubuntu 20.04 & 22.04 LTS / Debian 11 & 12 / Raspbian Buster or Bullseye
- Min 8GB RAM, 80GB HDD
- Private DNS entries matching the server IP address (needed for SSL) 
- Email relay permitted from the appliance's IP address
- An O365 (or similar service ) email enabled account with an app password configured
- The user executing the wget installer script **must be a member of the sudo group**

### **Configuring email reporting**
Setup scripts extend both the Docker and source build with a Postfix MTA installation. Be aware the Docker build is more of a hacky proof-of-concept because occasional factory container updates will overwrite the Postfix extended GVMD container back to standard. To combat this, after an update the Docker system checks to see if Postfix is still present, and if not re-installs it... but it wont automatically re-add your secure SMTP auth & relay settings. As such, a final step is to add your personal settings to `add-docker-smtp-relay-o365.sh` and then automate this script using the same cron tasks that automatically re-adds Postfix if it is missing.  For production use cases, the source build is recommended as it will mean a less complex & more static software environment. (By studying the contents of `add-smtp-relay-o365.sh` you will be able to more easily see the personalised inputs required to complete the a TLS SMTP-auth relay with Microsoft365 or other similar email service.)

### **To perform vulnerability scans with Windows SMB authentication**

1. Run the included powershell script on all Windows hosts to be scanned with SMB credentials. 
2. Create a GVM service account on all Windows hosts to be scanned, add this account to the local Administrators group.  (This service account must NOT be a built-in Windows account)
3. Create a new credentials object in the GVM management console that reflects the new Windows service account.
4. Create a scan target, populate it with the Windows devices to scan and then select the new credentials object for this target object.
5. Create a new scan task for the credentialed scan target created in step 4, then run or schedule this scan task.

#### *__SSL Note:__* 
For both build options, the Nginx SSL install creates Windows & Linux client certificates locally ($site.crt, $site.key & $site.pfx). Instructions for their import into client systems are provided at completion of either build script.

#### *__Docker build note:__* 
Maintainers at Greenbone occasionally break things and you may encounter QA inconsistencies with their Docker builds from time to time. (Feed updates require container updates that also introduce several other application updates as well). For production use, the source build will allow a more stable software environment.

#### *__Docker firewall note__* 
Be aware that in all cases, the Linux firewall leaves the default Docker install completely unprotected, and this is a Docker 'feature'. Docker's internal network and IPchain are in fact all processed BEFORE the Linux UFW firewall, therefore Docker traffic is all said and done before it ever hits any of your UFW rules. Docker's recommended approach is to force all containers to use 127.0.0.1 and proxy services outside, but this is a blunt and unsophisticated approach that will break systems with complex intra-container interactions such as GVM. To achieve granular control over Docker's IP chain and internal dynamic NAT, the setup script intercepts only GVM's web console traffic (by unmangling and blocking at the Docker NAT table via the ctorigdstport directive) and thus forces access though the SSL reverse proxy. The installer script makes this new firewall rule persistent on boot. Any additional firewall rules required should be added with the same technique.

