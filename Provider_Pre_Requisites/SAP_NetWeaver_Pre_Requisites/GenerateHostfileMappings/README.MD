## Generate hostfile mappings input for NetWeaver Provider in AMS

### Windows Virtual Machines

Steps:

1. Login to the application server using root user credentials.
2. Copy the "GenerateHostfileMappings.ps1" file to the Desktop on the SAP system instance.
3. Open powershell in the same directory and run the following command to execute the script:
```./GenerateHostfileMappings.ps1 -instanceNumber <instance_number>```
For example: ./GenerateHostfileMappings.ps1 -instanceNumber 00

### Linux Virtual Machines

Steps:

1. On the Azure Portal, navigate to the Central Server Virtual Machine.
2. In the search bar, type “Run Command”, select the Run Command option under Operations.
3. Select the “RunShellScript” option, this would open a contextual pane with input box.
4. Copy the script “GenerateHostfileMappings.sh” in the Linux Shell Script input box and replace the instance number on line 8, without any white spaces. If the instance number is incorrect, you will see the corresponding error under stderr.
5. Click the Run button, and it should take a few minutes to get the output.
6. Check for the output format, it should have a comma separated format of IP FQDN HOSTNAME, for example: 1.2.3.4 sapserver1.domain.com sapserver1, 1.2.3.5 sapserver2.domain.com sapserver2.
7. Copy the hostfile entries and use them while adding a provider for the system.
