Option Explicit
Dim shell, args, cmd, i, arg

Set shell = CreateObject("WScript.Shell")
Set args = WScript.Arguments

If args.Count = 0 Then
    WScript.Quit 1
End If

cmd = ""
For i = 0 To args.Count - 1
    arg = args(i)
    If InStr(arg, " ") > 0 And Left(arg, 1) <> """" Then
        arg = """" & arg & """"
    End If
    If i > 0 Then cmd = cmd & " "
    cmd = cmd & arg
Next

' Keep wscript running so Task Scheduler sees the real completion and exit code.
WScript.Quit shell.Run(cmd, 0, True)
