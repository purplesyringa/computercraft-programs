# metropanel

A service for showing the remaining time until the next train on a display.

Features:

* Automatic interpolation of observed navigation times, similarly to how Create itself does it
* Train movements are broadcast on rednet so that all displays know where trains are
* Almost zero-configuration

## Setup

metropanel runs on the `metropanel` seat. This has to be configured like follows:

```
hw add metropanel.monitor <monitor_network_id>
```

After this, the computer can be configured as a panel via:

```
svc reach metropanel --persist
```

## Station naming convention

In order for metropanel to work, train station names must follow the following naming convention:

`station_name = <human-readable station name> [per-station flags]`

See below for the list of allowed flags.

## Station naming convention for schedules

In order for metropanel to work, train station globs in schedules must follow the following convention:

`station_glob = <human-readable station name> [per-station flags]`

OR

`station_glob = <human-readable station name> {[per-route flags],}[per-station flags]`

No other globbing is allowed except for these two options. If the human-readable station name contains characters Create considers special in globs, they must be escaped accordingly.

Human-readable station name must be exactly the same in the station and in the route. No globbing is allowed, except for the escaping of special characters.

If a per-route flag is the same for all routes, it can be specified in both the station and the route (under per-station flags), and must be the same in both places. If a per-route flag is different for different routes, it must be specified only in the route under per-route flags.

See below for the list of allowed flags.

## Station flags

* `:r` &mdash; panel should use the Russian locale. This is a per-station flag.
* `:s` &mdash; this is a proper stop where passengers can board or unboard. Service stops, such as dead ends, are not proper stops. This is a per-route flag.
* `:t` &mdash; passengers are not allowed to travel to this station. This flag is appropriate for dead-ends which are past the passenger-visible platform of the terminal station. This is a per-route flag.
* `:<digit>` &mdash; discriminator, used to distinguish between different stations with the same name. This is a per-station flag.

## Examples

The following station is always a proper stop:

* Station name: `Example :s:1`
* Glob: `Example :s:1`

The following station is a proper stop in route 1, but a non-traversable station in route 2:

* Station name: `Example :2`
* Glob in route 1: `Example {:s,}:2`
* Glob in route 2: `Example {:t,}:2`

Note how a discriminant is used to differentiate between two stations both named "Example".

## Miscallenous

Stations are considered the same if their names and discriminants are both the same. Having two stations with the same name and discriminant, but otherwise distinct Create names, is undefined behavior.

Two trains are considered to follow the same route if their schedules specify the same stations in the same order. See above how station equality is cheched.

To avoid the computer running metropanel being unloaded, make it a turtle with a chunk vial.

Network connection is beneficial, but not required for the operation of metropanel. If there is no network, the panel will only use information provided by its own station to estimate waiting times.
