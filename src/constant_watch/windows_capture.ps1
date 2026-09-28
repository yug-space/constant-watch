param([ValidateSet('capture','status','permissions','request-accessibility','request-screen')][string]$Command = 'capture')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms, System.Runtime.WindowsRuntime
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CWDesktop {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint f, bool i, uint a);
 [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SwitchDesktop(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
 public delegate bool WindowVisitor(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, WindowVisitor visitor, IntPtr p);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder name, int count);
 [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 public static bool HasPasswordControl(IntPtr window) {
  bool found = false;
  EnumChildWindows(window, delegate(IntPtr h, IntPtr unused) {
   var name = new StringBuilder(256); GetClassName(h, name, name.Capacity);
   string type = name.ToString();
   if (IsWindowVisible(h) && (type.Equals("Edit", StringComparison.OrdinalIgnoreCase) || type.IndexOf("EDIT", StringComparison.OrdinalIgnoreCase) >= 0) && (GetWindowLong(h, -16) & 0x20) != 0) { found = true; return false; }
   return true;
  }, IntPtr.Zero);
  return found;
 }
 public struct RECT {public int Left,Top,Right,Bottom;}
}
'@
$null = [CWDesktop]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Emit($value) { $value | ConvertTo-Json -Depth 6 -Compress; exit 0 }
function Skip([string]$reason) { Emit @{ skipped=$reason; warnings=@(); accessibility=$true; screen_recording=$true } }
function Await-WinRT($operation, [Type]$resultType) {
 $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
 $task = $method.MakeGenericMethod($resultType).Invoke($null, @($operation))
 if (-not $task.Wait(5000)) { throw 'Windows OCR timed out' }
 return $task.Result
}
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Storage.Streams.DataWriter, Windows.Foundation, ContentType=WindowsRuntime]
$ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$desktop = [CWDesktop]::OpenInputDesktop(0, $false, 0x0100)
$unlocked = $desktop -ne [IntPtr]::Zero
if ($unlocked) { $unlocked = [CWDesktop]::SwitchDesktop($desktop); $null = [CWDesktop]::CloseDesktop($desktop) }
if ($Command -ne 'capture') {
 Emit @{ accessibility=$unlocked; screen_recording=$unlocked; ocr_available=($null -ne $ocrEngine); platform='windows'; warnings=@($(if ($null -eq $ocrEngine) {'Install an OCR language in Windows Settings > Time & language > Language & region.'})) }
}
if (-not $unlocked) { Skip 'Windows desktop is locked or unavailable' }
$window = [CWDesktop]::GetForegroundWindow()
if ($window -eq [IntPtr]::Zero) { Skip 'No foreground window' }
[uint32]$processId = 0
$null = [CWDesktop]::GetWindowThreadProcessId($window, [ref]$processId)
$process = Get-Process -Id $processId
$appId = 'windows:' + $process.ProcessName.ToLowerInvariant() + '.exe'
if (($env:CW_EXCLUDED_APPS -split "`n") -contains $appId) { Skip 'Excluded application' }
if ([CWDesktop]::HasPasswordControl($window)) { Skip 'Secure text field is visible' }
$element = [System.Windows.Automation.AutomationElement]::FromHandle($window)
$title = $element.Current.Name
if ($title -like '*Constant Watch*') { Skip 'Viewing Constant Watch' }
$clock = [Diagnostics.Stopwatch]::StartNew()
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$queue = New-Object 'System.Collections.Generic.Queue[System.Windows.Automation.AutomationElement]'
$nodes = New-Object 'System.Collections.Generic.List[System.Windows.Automation.AutomationElement]'
$queue.Enqueue($element)
# Inspect visible controls for password fields before reading values or pixels.
while ($queue.Count -gt 0) {
 if ($nodes.Count -ge 500 -or $clock.ElapsedMilliseconds -gt 8000) { Skip ('Accessibility tree exceeded privacy inspection limit (' + $nodes.Count + ' controls, ' + $clock.ElapsedMilliseconds + ' ms)') }
 $current = $queue.Dequeue()
 try {
  if ($current.Current.IsOffscreen) { continue }
  if ($current.Current.IsPassword) { Skip 'Secure text field is visible' }
  $nodes.Add($current)
  $child = $walker.GetFirstChild($current)
  while ($null -ne $child) {
   if ($queue.Count -ge 500 -or $clock.ElapsedMilliseconds -gt 8000) { Skip ('Accessibility tree exceeded privacy inspection limit (' + $nodes.Count + ' controls, ' + $clock.ElapsedMilliseconds + ' ms)') }
   $queue.Enqueue($child); $child = $walker.GetNextSibling($child)
  }
 } catch { Skip 'Window changed during privacy inspection' }
}
$lines = New-Object 'System.Collections.Generic.List[string]'
foreach ($current in $nodes) {
 if ($clock.ElapsedMilliseconds -gt 9000 -or ($lines -join "`n").Length -gt 12000) { break }
 try {
  if ($current.Current.IsPassword) { Skip 'Secure text field is visible' }
  $name = $current.Current.Name
  if ($name) { $lines.Add($name) }
  $pattern = $null
  if ($current.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) {
   foreach ($range in $pattern.GetVisibleRanges()) { $value=$range.GetText(12000); if ($value) { $lines.Add($value) } }
  } elseif ($current.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
   $value = $pattern.Current.Value
   if ($value) { $lines.Add($value.Substring(0, [Math]::Min(12000, $value.Length))) }
  }
 } catch { Skip 'Window changed during text capture' }
}
if ([CWDesktop]::GetForegroundWindow() -ne $window) { Skip 'Foreground window changed' }
if ([CWDesktop]::HasPasswordControl($window)) { Skip 'Secure text field is visible' }
$warnings = @()
$ocrText = ''
if ($null -ne $ocrEngine) {
 $bitmap=$null; $graphics=$null; $memory=$null; $stream=$null; $writer=$null; $software=$null
 try {
  $rect = New-Object CWDesktop+RECT
  if (-not [CWDesktop]::GetWindowRect($window, [ref]$rect)) { throw 'Window bounds unavailable' }
  $bounds = [System.Drawing.Rectangle]::FromLTRB($rect.Left,$rect.Top,$rect.Right,$rect.Bottom)
  $bounds = [System.Drawing.Rectangle]::Intersect($bounds, [System.Windows.Forms.SystemInformation]::VirtualScreen)
  if ($bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Width -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension -or $bounds.Height -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension) { throw 'Window size exceeds OCR limits' }
  $bitmap = New-Object System.Drawing.Bitmap($bounds.Width,$bounds.Height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location,[System.Drawing.Point]::Empty,$bounds.Size)
  $memory = New-Object System.IO.MemoryStream
  $bitmap.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png)
  $stream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
  $writer = New-Object Windows.Storage.Streams.DataWriter($stream)
  $writer.WriteBytes($memory.ToArray())
  $null = Await-WinRT ($writer.StoreAsync()) ([uint32])
  $null = $writer.DetachStream(); $stream.Seek(0)
  $decoder = Await-WinRT ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $software = Await-WinRT ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $result = Await-WinRT ($ocrEngine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult])
  $ocrText = $result.Text
 } catch { $warnings += 'Windows OCR unavailable: ' + $_.Exception.Message }
 finally { foreach ($resource in @($software,$writer,$stream,$memory,$graphics,$bitmap)) { if ($null -ne $resource) { $resource.Dispose() } } }
} else { $warnings += 'No Windows OCR language is installed. Accessibility text is still captured.' }
if ([CWDesktop]::GetForegroundWindow() -ne $window) { Skip 'Foreground window changed' }
Emit @{app_id=$appId; app_name=$process.ProcessName; window_title=$title; ax_text=(($lines | Select-Object -Unique) -join "`n"); ocr_text=$ocrText; warnings=@($warnings); accessibility=$true; screen_recording=$true}
