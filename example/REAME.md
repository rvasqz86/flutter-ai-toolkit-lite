```xml
<!--Plist-->
<key>UIFileSharingEnabled</key>
<true/>
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access for model inference services.</string>
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```
```text
Podfile
use_frameworks! :linkage => :static
```