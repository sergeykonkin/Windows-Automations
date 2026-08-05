Option Explicit

Dim programToStart, startAfter, objWMIService, colProcesses, processFound, shell

If WScript.Arguments.Count < 2 Then
    WScript.Echo "Usage: start-after.vbs <programToStart> <startAfter>"
    WScript.Quit 1
End If

programToStart = WScript.Arguments(0)
startAfter = WScript.Arguments(1)

Set shell = CreateObject("WScript.Shell")

Do
    processFound = False

    Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
    Set colProcesses = objWMIService.ExecQuery("Select * from Win32_Process Where Name = '" & startAfter & "'")

    If colProcesses.Count > 0 Then
        processFound = True
    Else
        WScript.Sleep 1000 ' wait 1 second
    End If
Loop Until processFound

shell.Run """" & programToStart & """", 1, False
