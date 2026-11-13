# iGlance reference assessment

Assessed 2026-11-13 at upstream commit `3d598cf` (commit date 2023-08-20). Source was cloned into a temporary directory for study. No GitHub fork was created and no iGlance application source has been imported into this repository.

## Findings

- `MenuBarItemManager` instantiates seven individual status-item classes. Each uses NSStatusItem, so the familiar native mechanism is suitable, but a combined compact renderer would be new work.
- Settings already support visibility, graph style, colours, graph width, refresh interval, and import/export. These are useful product references.
- `AppDelegate.updateLoop()` dispatches metric updates onto the main queue. Network updates invoke synchronous subprocesses through `executeCommand()`, including a route/grep/awk pipeline and netstat. Network counters are read more than once during a visible meter update.
- `NetworkInfo.getNetworkBandwidth()` divides counter deltas by the configured interval converted to UInt64, rather than measured elapsed time. Interface changes share a last-counter pair. A new implementation should use elapsed monotonic time and per-interface baselines.
- `CpuInfo.getCpuTemp()` queries SMCKit's CPU proximity sensor key. Successful compilation would not establish sensor support on current Apple silicon hardware.
- The project uses CocoaPods, Carthage, and submodules for SMCKit, SystemKit, and AppMover. Its Podfile.lock records CocoaPods 1.9.1, CocoaLumberjack 3.7.0, Sparkle 1.24.0, and SwiftLint 0.41.0. Carthage records LaunchAtLogin v4.0.0.

## Build-check limits

An unsigned project build with Xcode 27.2 failed before application compilation because generated CocoaPods configuration and file lists were absent, and the macOS 10.12 target was outside this toolchain's supported deployment range. The failure was reproduced outside the execution sandbox to separate project failures from sandbox warnings.

CocoaPods/Carthage were not installed for this assessment; missing submodules and dependency binaries were not restored. A full dependency-restored workspace build was not performed. There are no runtime compatibility, sensor accuracy, CPU, energy, app-size, or memory measurements from this assessment. The build failure is not proof that the application source cannot be modernized.

## Conclusion

Continuing iGlance is feasible as an investigation, but the proposed combined icon, background native sampling, modern dependency setup, and hardware validation would still require substantial work. A new native application is the recommended fit for this product. Its implementation should use independently written code and appropriately licensed dependencies.

## Source references

All references below are pinned to the assessed upstream revision.

- [Menu-bar manager](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/iGlance/MenuBarItems/MenuBarItemManager.swift)
- [Application update loop](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/iGlance/AppDelegate.swift)
- [Network reader](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/iGlance/SystemInfo/NetworkInfo.swift)
- [Synchronous subprocess helper](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/iGlance/SystemInfo/Utils.swift)
- [CPU reader](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/iGlance/SystemInfo/CpuInfo.swift)
- [User settings](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/iGlance/UserSettings.swift)
- [Podfile.lock](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/Podfile.lock)
- [Carthage versions](https://github.com/iglance/iGlance/blob/3d598cf/iGlance/iGlance/Cartfile.resolved)
- [Contribution/build instructions](https://github.com/iglance/iGlance/blob/3d598cf/.github/CONTRIBUTING.md)
