# Automating Azure Analysis Services - Code Samples
My [SQL Saturday presentation](http://www.sqlsaturday.com/734/Sessions/Details.aspx?sid=77768) (slides available after May 19, 2018) included demos of various ways to automate Azure Analysis Services. These code samples are included here.

### AutoStartAzureAS
On premises solutions typically run at full scale 24 hours a day and 7 days a week. The cloud brings elasticity which allows the solution to scale down during off periods or burst up to meet peak capacity. Often this scaling is done on a schedule. The downside of scaling on a predictable schedule is that users don't always operate on a predictable schedule.

The AutoStartAzureAS code sample is will start your Azure Analysis Services when the first user connects. This solution is a bit experimental. It may be a better choice for the Test environment rather than a Production environment until it proves to be stable in the real world. Leave a note on the Issues page sharing any real-world experience with this sample code.

Other samples will be responsible for pausing Azure Analysis Services if there are no user queries for a period of time.

#### Deployment:

Edit the applicationSettings section in the Web.config:
* **SubscriptionID** - The GUID identifier for the subscription the Azure Analysis Services instance is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **ResourceGroup** - The name of the resource group where the Azure Analysis Services instance lives.
* **ServerName** - The name of your Azure Analysis Services instance. This is not the full asazure:// URI. This is just the final section saying the name of your server.

Then click Publish and publish to Azure App Service. Purchase (or use free [Let's Encrypt](https://github.com/hansenms/LetsEncryptWebApp/) on a non-production server) a valid SSL certificate for your website as the link:// syntax uses HTTPS under the covers and will fail without a valid SSL cert. Finally, on the blade for your App Service go to the Managed Service Identity tab and set "Register with Azure Active Directory" to On so that MSI authentication is enabled. Then go to the blade for your Azure Analysis Services server and the Access Control (IAM) tab and add Contribute access to the MSI (choose Assign access to = App Service then choose the web app).

#### Excel Usage:

On the Data tab click Existing Connections... Browse for More... then paste in a URL like this (http or https):

https://MyWebsiteNameHere.azurewebsites.net/AutoStart/ODC/MyDatabaseName/MyCubeName

#### Other Client Tool Usage:

For tools such as SQL Server Management Studio and Power BI Desktop, in the server name use the following:

link://MyWebsiteNameHere.azurewebsites.net/AutoStart/

Under the covers that will use https so ensure that you have a proper SSL certification enabled.

Excel imposes a 30 second timeout when resolving the link:// URI which does not allow enough time for Azure Analysis Services to start. Follow the Excel Usage example above.

Though Power BI Desktop appears to work well, the Power BI website has a pretty strict timeout which does not allow Azure Analysis Services time to start. There are no known workarounds for this at the moment. If you have a suggestion, leave one on the Issues tab.


### ADFv2

#### ResumeAzureAS

The ADFv2/ResumeAzureAS.json file contains an Azure Data Factory v2 pipeline which is able to resume Azure AS looping until the resume is complete. It uses only Web Activities. There are no dependencies on .NET custom activities or Azure Logic Apps or SSIS.

Set the following parameters upon execution of the pipeline:
* **TenantID** - The GUID identifier for your Azure Active Directory (AAD) tenant. In the Azure Portal go to the Azure Active Directory tab and the Properties tab and copy the Directory ID property.
* **ClientID** - The GUID identifier for the AAD application (sometimes called service principal). The ClientID is sometimes called the ApplicationID. In the Azure Portal go to the Azure Active Directory tab, the App Registrations tab, if you don't see the application in question, choose All apps from the dropdown. Click the application in question and copy the Application ID from the app's blade. If you haven't created the app yet, then follow these [instructions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal).
* **ClientSecret** - The secret key used to authenticate the AAD application. See these [instructions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal) for how to create the app and the key.
* **SubscriptionID** - The GUID identifier for the subscription the Azure Analysis Services instance is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **ResourceGroup** - The name of the resource group where the Azure Analysis Services instance lives.
* **Server** - The name of your Azure Analysis Services instance. This is not the full asazure:// URI. This is just the final section saying the name of your server.

The AAD application must be granted contribute permissions in the Access Control (IAM) in the Azure Analysis Services.


#### ProcessAzureAS

The ADFv2/ProcessAzureAS.json file (along with ADFv2/dsHttpApiAzureASRefreshes.json and ADFv2/lsHttpApiAzureAS.json files) show how to perform a full refresh of the data inside an Azure Analysis Services model. Unlike other solutions which leverage external services like Azure Logic Apps or custom ADF .NET activities running in Azure Batch, this approach uses only built-in activities which depend on no external services other than Azure Analysis Services.

Set the following parameters upon execution of the pipeline:
* **TenantID** - The GUID identifier for your Azure Active Directory (AAD) tenant. In the Azure Portal go to the Azure Active Directory tab and the Properties tab and copy the Directory ID property.
* **ClientID** - The GUID identifier for the AAD application (sometimes called service principal). The ClientID is sometimes called the ApplicationID. In the Azure Portal go to the Azure Active Directory tab, the App Registrations tab, if you don't see the application in question, choose All apps from the dropdown. Click the application in question and copy the Application ID from the app's blade. If you haven't created the app yet, then follow these [instructions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal).
* **ClientSecret** - The secret key used to authenticate the AAD application. See these [instructions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal) for how to create the app and the key.
* **SubscriptionID** - The GUID identifier for the subscription the Azure Analysis Services instance is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **Region** - The name of the region (e.g. southcentralus) where the Azure Analysis Services instance lives. This region is used as the beginning of the asazure:// server name for your server.
* **Server** - The name of your Azure Analysis Services instance. This is not the full asazure:// URI. This is just the final section saying the name of your server.
* **DatabaseName** - The name of the database in Azure Analysis Services you wish to process.

The AAD application must have admin permissions in SSAS. This is not accomplished through the Azure portal but through SQL Server Management Studio as described [here](https://azure.microsoft.com/en-us/blog/automation-of-azure-analysis-services-with-service-principals-and-powershell/).


### LinkedServer

Connecting to Azure Analysis Services with a SQL Server linked server enables a number of scenarios:

* Loading into SQL Server the results from a DMV (dynamic management view) to extract lists of measures or tables
* Loading into SQL Server the results from a MDX or DAX query
* Executing TMSL commands to refresh the data in Azure Analysis Services models

The "LinkedServer/SQL Linked Server to Azure Analysis Services.sql" file shows an example of the linked server setup and how to use it.


### SSIS

If your ETL is orchestrated in SQL Server Integration Services, it is only natural to refresh your Azure Analysis Services models using SSIS. We prefer C# script tasks for cube processing over the Analysis Services Processing command because the Analysis Services Processing command hardcodes the SSAS database at design time while the C# code can process the database identified in the connection string such that runtime configuration can cause it to process a different database.

* **SSIS/ProcessAzureAS-UsernamePassword.dtsx** - An SSIS package which authenticates using a username and password (which does not have multi-factor auth enabled) and performs a full refresh of the model. This package uses a C# script task. Follow the instructions in the annotation once you open the SSIS package.
* **SSIS/ProcessAzureAS-App.dtsx** - An SSIS package which authenticates using an AAD application (ClientID and secret). This package uses a C# script task. Follow the instructions in the annotation once you open the SSIS package.

### GeographicLoadBalancing

Using Azure Traffic Manager it is possible to build a solution which redirects users to the geographically closest Azure Analysis Services. This [blog post](https://www.artisconsulting.com/blogs/greggalloway/2018/5/11/sending-users-to-the-geographically-nearest-azure-analysis-services) walks through the configuration of this solution. The code is really just one line but is found at AutoStartAzureAS/Default.aspx.cs



### Proposing Changes

Enhancements to code or documentation are welcome. Create a pull request.
