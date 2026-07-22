# Programs for ComputerCraft

This repo contains applications me and my friends made for [CC: Tweaked](https://tweaked.cc):

- [Instant storage](sys/packages/storage), which can deliver items from a single server to multiple interactive clients. As you write the search query in the client, 1 stack of each matching item is almost instantly pulled into its inventory for preview and quick pulling, producing very nice UX. If you install Turtlematic, UnlimitedPeripheralWorks, and Create, you'll also get wireless clients that you can carry in your inventory to deposit or withdraw items from any point in the world.

- [A smart supersmelter](sys/packages/supersmelter) that can spread items across blast furnaces and normal furnaces, automatically crafting and decrafting storage blocks.

- [A timetable display](sys/packages/metropanel) for Create trains, compact and more precise.

- [A sound tool](sys/packages/phaseroll) that plays a sound that seemingly originates from somewhere other than the speaker.

The applications are built on top of a custom rudimentary OS, but since there is no long-winded installation process, this shouldn't be too confusing.


## Quick start

Install the OS and all the applications with a single command:

```shell
wget https://cc.purplesyringa.moe/initrd.lua startup.lua
```

Reboot the computer. You should be facing a slightly improved command prompt.

You can now execute programs directly as usual, or tell the OS to run a program on each boot. For example, for the storage server, you want:

```shell
svc reach storage-server --persist
```

The names and installation procedures are different for all applications. See the documentation for the app for specific information.


## Network boot

If your device list grows past 5 computers or so, you may be interested in centralized updates. With network boot, all computers but one fetch the `initrd.lua` file from a single *file server* over ender modems, so updating `startup.lua` on the file server is sufficient to update all computers (after reboot).

To set this up, install the OS on the file server and activate the `fileserver` target:

```shell
wget https://cc.purplesyringa.moe/initrd.lua startup.lua
reboot
svc reach fileserver --persist
```

On all other computers, fetch `startup.lua` from `netboot.lua` instead of `initrd.lua`:

```shell
wget https://cc.purplesyringa.moe/netboot.lua startup.lua
```


## Maintenance

If something doesn't behave as expected or you make a mistake, you'll need to learn how to use a few utilities. The important ones are:

- [Remote shell](sys/packages/rsh). You can connect to any computer running this OS with `rsh <hostname>`, where the hostname can be configured with `hostname <hostname>`. If the hostname has not been configured ahead of time, use `rsh <computer-id>`. Computers connected to the network respond to `online [glob]` calls even without hostname configured.

- [Service manager](sys/packages/svc). `svc` shows the list of services (programs) running on the computer and their failures. Use `svc status <service-name>` for error logs, `svc stop <service-name>`/`svc start <service-name>` to manipulate services. You can change which services are started on boot with `svc reach <target-name> --persist`; the `base` target is the default "empty" one.

- [System updater](sys/packages/resys). The `resys` program fetches the most recent OS image from web and updates `startup.lua` accordingly. Note that we don't guarantee stability, so things might break.


## Development

Do you want to know more about how this whole thing works, or maybe even add a new application? Check out [the hacking guide](HACKING.md).
