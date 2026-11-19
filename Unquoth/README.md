Unquoth.ps1 — tests writability for the entire tree of an unquoted service path

Given a service binary path (typically one containing a space with no quotes, e.g. C:\Program Files\Some App\svc.exe), Unquoth walks from the binary's parent directory up to the drive root, attempting to create a uniquely-named temp file in each level. Every directory where the write succeeds is printed as [+] WRITABLE, every one where it fails as [-] NOT WRITABLE.

Because an unquoted service path is only exploitable if Windows' path resolver would hit one of those writable directories before reaching the real binary — so the first WRITABLE line below the "Program Files" boundary is a hijack point. After finding any unquoted binaries, this reduces the time it takes to verify down to a single second.

What to tweak in-code:

• $TargetPath — full path to the service binary (from wmic service get name,pathname or sc qc <svc>); use the raw, unquoted path as Windows reports it
