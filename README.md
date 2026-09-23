# SVoA (SysVer for Android)

SysVer is a dependency-free, sourceable Android shell library that exposes a
consistent snapshot of useful device and runtime information. It works with
Android's `getprop`, procfs, and the standard toybox utilities already present
on modern devices.

## Usage

Copy `sysver.sh` into an app's scripts/assets directory, make it executable,
and either run it directly or source it from another shell script:

```sh
# JSON snapshot
./sysver.sh

# Use the library API
. ./sysver.sh
android_release=$(sysver_value android_version)
model=$(sysver_value phone_name)
sysver_collect
```

`sysver_collect` prints one JSON object. Values that cannot be read on a
particular device are `null`; this is expected because Android permissions,
vendors, and kernels expose different system data.

## Reported fields

- Android and kernel versions, architecture, Java version, and phone name
- Processor model, physical/logical CPU counts, and frequency when available
- Load average when `/proc/loadavg` is supported
- Non-loopback IPv4/IPv6 addresses
- Uptime in seconds and calculated boot time (Unix epoch seconds)
- Memory total, available, used, and usage percentage in bytes/percent
- Capacity, free space, and usage percentage for `/data` (or `/` as fallback)

## License

MIT; see [LICENSE](LICENSE).
