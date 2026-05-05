using System.Diagnostics;
using System.Runtime.InteropServices;
using LocalWhisper.Windows.Interop;

namespace LocalWhisper.Windows.Services;

// A process-wide Job Object configured with KillOnJobClose. Any child process
// assigned to it dies automatically when this process exits — including hard
// crashes, taskkill /F, or unhandled native exceptions where managed cleanup
// never runs. This is the only reliable way on Windows to guarantee that
// whisper-server.exe never outlives the launching app.
internal static class ChildProcessJob
{
    private static readonly object Gate = new();
    private static nint _handle;
    private static bool _initFailed;

    public static bool TryAssign(Process process)
    {
        lock (Gate)
        {
            if (_initFailed)
            {
                return false;
            }

            if (_handle == nint.Zero && !TryCreate())
            {
                _initFailed = true;
                return false;
            }

            try
            {
                return NativeMethods.AssignProcessToJobObject(_handle, process.Handle);
            }
            catch
            {
                return false;
            }
        }
    }

    private static bool TryCreate()
    {
        var job = NativeMethods.CreateJobObject(nint.Zero, null);
        if (job == nint.Zero)
        {
            return false;
        }

        var info = new NativeMethods.JobObjectExtendedLimitInformationStruct
        {
            BasicLimitInformation = new NativeMethods.JobObjectBasicLimitInformation
            {
                LimitFlags = NativeMethods.JobObjectLimitKillOnJobClose
            }
        };

        var size = Marshal.SizeOf<NativeMethods.JobObjectExtendedLimitInformationStruct>();
        var ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(info, ptr, fDeleteOld: false);
            if (!NativeMethods.SetInformationJobObject(
                    job,
                    NativeMethods.JobObjectExtendedLimitInformation,
                    ptr,
                    (uint)size))
            {
                NativeMethods.CloseHandle(job);
                return false;
            }
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }

        _handle = job;
        return true;
    }
}
