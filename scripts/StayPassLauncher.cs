using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Sockets;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("StayPass Desktop Launcher & Installer")]
[assembly: AssemblyDescription("Instalador y Ejecutable de Escritorio para StayPass QR y Panel del Propietario")]
[assembly: AssemblyCompany("StayPass Hospitality")]
[assembly: AssemblyProduct("StayPass PMS & Check-in QR")]
[assembly: AssemblyVersion("1.2.0.0")]

namespace StayPassLauncher
{
    public class MainForm : Form
    {
        private Label statusLabel;
        private string rootDir;

        public MainForm()
        {
            this.Text = "StayPass · Centro de Control e Instalador PC";
            this.Size = new Size(540, 440);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.BackColor = Color.FromArgb(19, 21, 24);
            this.ForeColor = Color.FromArgb(242, 239, 233);
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            rootDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            if (!File.Exists(Path.Combine(rootDir, "iniciar-staypass.bat")))
            {
                string parent = Directory.GetParent(rootDir) != null ? Directory.GetParent(rootDir).FullName : rootDir;
                if (File.Exists(Path.Combine(parent, "iniciar-staypass.bat")))
                {
                    rootDir = parent;
                }
            }

            Label title = new Label();
            title.Text = "StayPass · Panel del Propietario & App QR";
            title.Font = new Font("Segoe UI", 15f, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(210, 173, 109);
            title.Location = new Point(24, 20);
            title.AutoSize = true;
            this.Controls.Add(title);

            Label subtitle = new Label();
            subtitle.Text = "Ejecuta el ecosistema completo en tu PC, abre las aplicaciones en modo ventana nativa\no crea accesos directos en tu Escritorio.";
            subtitle.ForeColor = Color.FromArgb(160, 165, 174);
            subtitle.Location = new Point(24, 52);
            subtitle.Size = new Size(480, 42);
            this.Controls.Add(subtitle);

            statusLabel = new Label();
            statusLabel.Text = "Verificando servicios locales...";
            statusLabel.ForeColor = Color.FromArgb(82, 158, 126);
            statusLabel.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            statusLabel.Location = new Point(24, 98);
            statusLabel.Size = new Size(480, 22);
            this.Controls.Add(statusLabel);

            Button btnOwner = CreateStyledButton(
                "🏨  Abrir Panel del Propietario (App Escritorio)",
                new Point(24, 132),
                Color.FromArgb(210, 173, 109),
                Color.FromArgb(23, 22, 20)
            );
            btnOwner.Click += (s, e) => LaunchApp("http://localhost:8082", "Panel del Propietario");
            this.Controls.Add(btnOwner);

            Button btnGuest = CreateStyledButton(
                "📱  Abrir App del Huésped (StayPass QR)",
                new Point(24, 184),
                Color.FromArgb(107, 154, 184),
                Color.White
            );
            btnGuest.Click += (s, e) => LaunchApp("http://localhost:8081", "App del Huésped");
            this.Controls.Add(btnGuest);

            Button btnApks = CreateStyledButton(
                "📲  Descargar APKs para Celular Android (QR Wi-Fi)",
                new Point(24, 236),
                Color.FromArgb(82, 158, 126),
                Color.White
            );
            btnApks.Click += (s, e) => LaunchApp("http://localhost:8083/descargar", "Portal de Descarga APK");
            this.Controls.Add(btnApks);

            Button btnInstallShortcuts = CreateStyledButton(
                "💻  Instalar Accesos Directos en mi Escritorio de Windows",
                new Point(24, 288),
                Color.FromArgb(34, 38, 44),
                Color.FromArgb(242, 239, 233)
            );
            btnInstallShortcuts.Click += (s, e) => InstallDesktopShortcuts();
            this.Controls.Add(btnInstallShortcuts);

            Button btnAll = CreateStyledButton(
                "🚀  Iniciar Todo (Backend + Panel + App + Kiosco QR)",
                new Point(24, 340),
                Color.FromArgb(34, 38, 44),
                Color.FromArgb(210, 173, 109)
            );
            btnAll.Click += (s, e) => {
                EnsureServicesRunning();
                OpenAppWindow("http://localhost:8082");
                OpenAppWindow("http://localhost:8081");
            };
            this.Controls.Add(btnAll);

            this.Load += (s, e) => EnsureServicesRunning();
        }

        private Button CreateStyledButton(string text, Point location, Color bg, Color fg)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.Location = location;
            btn.Size = new Size(476, 42);
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderColor = Color.FromArgb(55, 60, 68);
            btn.FlatAppearance.BorderSize = 1;
            btn.BackColor = bg;
            btn.ForeColor = fg;
            btn.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
            btn.Cursor = Cursors.Hand;
            return btn;
        }

        private bool IsPortOpen(int port)
        {
            try
            {
                using (TcpClient client = new TcpClient())
                {
                    var result = client.BeginConnect("127.0.0.1", port, null, null);
                    var success = result.AsyncWaitHandle.WaitOne(TimeSpan.FromMilliseconds(350));
                    return success && client.Connected;
                }
            }
            catch
            {
                return false;
            }
        }

        public void EnsureServicesRunning()
        {
            bool apiUp = IsPortOpen(3000);
            bool webUp = IsPortOpen(8082);

            if (!apiUp)
            {
                string backendDir = Path.Combine(rootDir, "backend");
                if (Directory.Exists(backendDir))
                {
                    ProcessStartInfo psi = new ProcessStartInfo("node", "src/server.js");
                    psi.WorkingDirectory = backendDir;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                    psi.CreateNoWindow = true;
                    try { Process.Start(psi); } catch { }
                }
            }

            if (!webUp)
            {
                string scriptPath = Path.Combine(rootDir, "scripts", "serve-web-apps.js");
                if (File.Exists(scriptPath))
                {
                    ProcessStartInfo psi = new ProcessStartInfo("node", "\"" + scriptPath + "\"");
                    psi.WorkingDirectory = rootDir;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;
                    psi.CreateNoWindow = true;
                    try { Process.Start(psi); } catch { }
                }
            }

            statusLabel.Text = "● Servicios activos en vivo: API (:3000) · Panel (:8082) · App (:8081)";
        }

        private void LaunchApp(string url, string name)
        {
            EnsureServicesRunning();
            statusLabel.Text = "Abriendo " + name + "...";
            OpenAppWindow(url);
        }

        public static void OpenAppWindow(string url)
        {
            string[] browsers = new string[] {
                @"C:\Program Files\Google\Chrome\Application\chrome.exe",
                @"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                @"C:\Program Files\Microsoft\Edge\Application\msedge.exe"
            };

            foreach (string b in browsers)
            {
                if (File.Exists(b))
                {
                    try
                    {
                        Process.Start(b, "--app=" + url + " --window-size=1280,860");
                        return;
                    }
                    catch { }
                }
            }

            try { Process.Start(url); } catch { }
        }

        private void InstallDesktopShortcuts()
        {
            try
            {
                string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string exePath = Application.ExecutablePath;
                string vbsPath = Path.Combine(Path.GetTempPath(), "create_staypass_shortcuts.vbs");

                string vbs =
                    "Set sh = CreateObject(\"WScript.Shell\")\r\n" +
                    "Set s1 = sh.CreateShortcut(\"" + Path.Combine(desktop, "StayPass - Panel del Propietario.lnk") + "\")\r\n" +
                    "s1.TargetPath = \"" + exePath + "\"\r\n" +
                    "s1.Arguments = \"--owner\"\r\n" +
                    "s1.WorkingDirectory = \"" + rootDir + "\"\r\n" +
                    "s1.Description = \"Abrir StayPass Panel del Propietario\"\r\n" +
                    "s1.Save\r\n" +
                    "Set s2 = sh.CreateShortcut(\"" + Path.Combine(desktop, "StayPass QR - App Clientes.lnk") + "\")\r\n" +
                    "s2.TargetPath = \"" + exePath + "\"\r\n" +
                    "s2.Arguments = \"--guest\"\r\n" +
                    "s2.WorkingDirectory = \"" + rootDir + "\"\r\n" +
                    "s2.Description = \"Abrir StayPass QR App del Huésped\"\r\n" +
                    "s2.Save\r\n" +
                    "Set s3 = sh.CreateShortcut(\"" + Path.Combine(desktop, "StayPass - Centro de Control.lnk") + "\")\r\n" +
                    "s3.TargetPath = \"" + exePath + "\"\r\n" +
                    "s3.WorkingDirectory = \"" + rootDir + "\"\r\n" +
                    "s3.Description = \"Centro de Control StayPass\"\r\n" +
                    "s3.Save\r\n";

                File.WriteAllText(vbsPath, vbs);
                Process p = Process.Start("wscript.exe", "//B //Nologo \"" + vbsPath + "\"");
                if (p != null) p.WaitForExit(3000);

                statusLabel.Text = "✅ ¡Accesos directos instalados en tu Escritorio de Windows!";
                MessageBox.Show(
                    "Se crearon 3 accesos directos en tu Escritorio:\n\n" +
                    "1. StayPass - Panel del Propietario\n" +
                    "2. StayPass QR - App Clientes\n" +
                    "3. StayPass - Centro de Control",
                    "Instalación Completada",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information
                );
            }
            catch (Exception ex)
            {
                MessageBox.Show("No se pudieron crear los accesos directos: " + ex.Message);
            }
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            MainForm form = new MainForm();
            if (args.Length > 0)
            {
                form.EnsureServicesRunning();
                if (args[0] == "--owner")
                {
                    OpenAppWindow("http://localhost:8082");
                    return;
                }
                if (args[0] == "--guest")
                {
                    OpenAppWindow("http://localhost:8081");
                    return;
                }
            }

            Application.Run(form);
        }
    }
}
