using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using Microsoft.IdentityModel.Clients.ActiveDirectory;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Azure.Services.AppAuthentication;

namespace AutoStartAzureAS.AutoStart
{
    public partial class Default : System.Web.UI.Page
    {
        protected string resourceURI = "https://management.core.windows.net/";
        protected string subscriptionID = Properties.Settings.Default.SubscriptionID;
        protected string resourcegroup = Properties.Settings.Default.ResourceGroup;
        protected string server = Properties.Settings.Default.ServerName;
        protected string accessToken = null;
        protected string serverFullURI = null;
        protected const int TimeoutSeconds = 600;

        /// <summary>
        /// Resumes Azure AS if it's paused and then returns a link:// URI pointing at Azure AS
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        protected async void Page_Load(object sender, EventArgs e)
        {
            Response.Expires = -1;
            Response.CacheControl = "no-cache";

            var timeoutCancellationTokenSource = new CancellationTokenSource();
            var task = PerformActions(timeoutCancellationTokenSource);
            if (await Task.WhenAny(task, Task.Delay(TimeoutSeconds * 1000, timeoutCancellationTokenSource.Token)) == task)
            {
                // task completed within timeout
                timeoutCancellationTokenSource.Cancel(); //cancel the Task.Delay task
                await task; //give it a chance to rethrow errors
            }
            else
            {
                timeoutCancellationTokenSource.Cancel(); //cancel the PerformActions task
                throw new TimeoutException();
            }

            Response.Write(serverFullURI);
        }

        protected async Task<bool> PerformActions(CancellationTokenSource cancellationToken)
        {
            await GetAccessToken();

            string state = await GetAzureASState();
            if (state == "Paused")
            {
                await ResumeAzureAS();
            }
            if (state != "Succeeded")
            {
                //TODO: handle scenario when someone tries to connect right when it is pausing
                while ((await GetAzureASState()) != "Succeeded")
                {
                    if (cancellationToken.IsCancellationRequested)
                        return false;
                }
            }
            return true;
        }

        protected async Task<bool> ResumeAzureAS()
        {
            HttpClient client = new HttpClient();
            var apiURI = new Uri(string.Format("https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.AnalysisServices/servers/{2}/resume?api-version=2016-05-16", subscriptionID, resourcegroup, server));

            client.DefaultRequestHeaders.Accept.Clear();
            client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

            HttpResponseMessage response = await client.PostAsync(apiURI.ToString(), null);
            response.EnsureSuccessStatusCode();
            return true;
        }

        protected async Task<string> GetAzureASState()
        {
            HttpClient client = new HttpClient();
            var apiURI = new Uri(string.Format("https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.AnalysisServices/servers/{2}?api-version=2016-05-16", subscriptionID, resourcegroup, server));

            client.DefaultRequestHeaders.Accept.Clear();
            client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

            HttpResponseMessage response = await client.GetAsync(apiURI.ToString());
            response.EnsureSuccessStatusCode();
            string sJson = await response.Content.ReadAsStringAsync();
            var dictResult = Newtonsoft.Json.JsonConvert.DeserializeObject<Dictionary<string, object>>(sJson);
            if (!dictResult.ContainsKey("properties")) return null;
            var dictProperties = dictResult["properties"] as Newtonsoft.Json.Linq.JObject;
            if (dictProperties == null || !dictProperties.ContainsKey("state")) return null;
            string sState = Convert.ToString(dictProperties["state"]);

            if (dictProperties.ContainsKey("serverFullName"))
                serverFullURI = Convert.ToString(dictProperties["serverFullName"]);

            return sState;
        }

        protected async Task<string> GetAccessToken()
        {
            var azureServiceTokenProvider = new AzureServiceTokenProvider();
            this.accessToken = await azureServiceTokenProvider.GetAccessTokenAsync(resourceURI);
            return this.accessToken;

            //if you haven't enabled the Managed Service Identity then do it the old fashioned way...
            //AuthenticationContext ac = new AuthenticationContext(authority);
            //ClientCredential cred = new ClientCredential(clientID, clientSecret);
            //AuthenticationResult ar = await ac.AcquireTokenAsync(resourceURI, cred);
            //this.accessToken = ar.AccessToken;
            //return this.accessToken;
        }
    }
}