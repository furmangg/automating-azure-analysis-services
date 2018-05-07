using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;

namespace AutoStartAzureAS
{
    public partial class _Default : Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            //this is the hardcoded approach which doesn't autostart
            //could make this a config or could take the same approach as AutoStart/Default.aspx.cs
            this.Response.Write("asazure://southcentralus.asazure.windows.net/yourservername");
        }
    }
}