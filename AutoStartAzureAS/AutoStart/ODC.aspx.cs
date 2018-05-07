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
    public partial class ODC : AutoStart.Default
    {
        /// <summary>
        /// Resumes Azure AS if it's paused and then returns a .odc file which points at it
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        protected async new void Page_Load(object sender, EventArgs e)
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

            string database = "YouDidNotSpecifyDB";
            if (Request.Url.Segments.Length > 3) database = Request.Url.Segments[3].Replace("/","");
            string cube = "YouDidNotSpecifyCube";
            if (Request.Url.Segments.Length > 4) cube = Request.Url.Segments[4].Replace("/", "");

            string title = server + " " + database;

            Response.ContentType = "text/x-ms-odc";
            string odc = GetResourceFileContents("AutoStartAzureAS.AutoStart.Model.odc");
            //can't use string.Format because of the JavaScript code { } in the ODC template
            odc = odc.Replace("{title}", title);
            odc = odc.Replace("{serverFullURI}", serverFullURI);
            odc = odc.Replace("{database}", database);
            odc = odc.Replace("{cube}", cube);
            Response.Write(odc);
        }
        
        private string GetResourceFileContents(string name)
        {
            using (var stream = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                using (var streamReader = new System.IO.StreamReader(stream))
                {
                    return streamReader.ReadToEnd();
                }
            }

        }
    }
}