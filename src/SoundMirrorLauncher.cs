using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("SoundMirror")]
[assembly: AssemblyProduct("SoundMirror")]
[assembly: AssemblyDescription("Stream your phone's audio and screen to this PC")]
[assembly: AssemblyCompany("SoundMirror")]
[assembly: AssemblyInformationalVersion("0.2.0")]
[assembly: AssemblyVersion("0.2.0.0")]
[assembly: AssemblyFileVersion("0.2.0.0")]

namespace SoundMirror
{
    internal static class Program
    {
        [STAThread]
        private static int Main()
        {
            string dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            string script = Path.Combine(dir, "sound-mirror.ps1");

            if (!File.Exists(script))
            {
                MessageBox.Show(
                    "找不到 sound-mirror.ps1。\n\n请确认它和本程序放在同一个目录：\n" + dir,
                    "SoundMirror",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");

            if (!File.Exists(powershell))
            {
                MessageBox.Show(
                    "找不到系统自带的 Windows PowerShell：\n" + powershell,
                    "SoundMirror",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = powershell;
            // 不要加 -WindowStyle Hidden：那会把 WinForms 窗体一起隐藏
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;

            try
            {
                using (Process p = Process.Start(psi))
                {
                    if (p == null)
                    {
                        MessageBox.Show("启动界面失败。", "SoundMirror",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 1;
                    }
                    p.WaitForExit();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "启动失败：\n" + ex.Message,
                    "SoundMirror",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }

            return 0;
        }
    }
}
