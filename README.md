# Automating Azure Analysis Services - Code Samples
My [SQL Saturday presentation](http://www.sqlsaturday.com/734/Sessions/Details.aspx?sid=77768) (slides available after May 19, 2018) included demos of various ways to automate Azure Analysis Services. These code samples are included here.

### AutoStartAzureAS
On premises solutions typically run at full scale 24 hours a day and 7 days a week. The cloud brings elasticity which allows the solution to scale down during off periods or burst up to meet peak capacity. Often this scaling is done on a schedule. The downside of scaling on a predictable schedule is that users don't always operate on a predictable schedule.

The AutoStartAzureAS code sample is will start your Azure Analysis Services when the first user connects. This solution is a bit experimental. It may be a better choice for the Test environment rather than a Production environment until it proves to be stable in the real world.

Other samples will be responsible for pausing Azure Analysis Services if there are no user queries for a period of time.

##### Deployment:

Edit the applicationSettings section in the Web.config:
* **SubscriptionID** - The GUID identifier for the subscription the Azure Analysis Services instance is running from. To get this ID, go to the Subscriptions tab of the Azure Portal.
* **ResourceGroup** - The name of the resource group where the Azure Analysis Services instance lives.
* **ServerName** - The name of your Azure Analysis Services instance. This is not the full asazure:// URI. This is just the final section saying the name of your server.

Then click Publish and publish to Azure App Service. Purchase (or use [Let's Encrypt](https://github.com/hansenms/LetsEncryptWebApp/) on a non-production server) a valid SSL certificate for your website as the link:// syntax uses HTTPS under the covers and will fail without a valid SSL cert. Finally, on the blade for your App Service go to the Managed Service Identity tab and set "Register with Azure Active Directory" to On so that MSI authentication is enabled.

##### Excel Usage:

On the Data tab click Existing Connections... Browse for More... then paste in a URL like this (http or https):

https://MyWebsiteNameHere.azurewebsites.net/AutoStart/ODC/MyDatabaseName/MyCubeName

##### Other Client Tool Usage:

For tools such as SQL Server Management Studio and Power BI Desktop, in the server name use the following:

link://MyWebsiteNameHere.azurewebsites.net/AutoStart/

Under the covers that will use https so ensure that you have a proper SSL certification enabled.

Excel imposes a 30 second timeout when resolving the link:// URI which does not allow enough time for Azure Analysis Services to start. Follow the Excel Usage example above.

Though Power BI Desktop appears to work well, the Power BI website has a pretty strict timeout which does not allow Azure Analysis Services time to start. There are no known workarounds for this at the moment. If you have a suggestion, leave one on the Issues tab.



### Proposing Changes

Enhancements to code or documentation are welcome. Create a pull request.
