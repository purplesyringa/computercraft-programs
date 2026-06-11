# hardware

This package allows peripherals to be named and grouped together, forming *devices* that can be easily used as a whole without manually passing raw peripheral names to each application.

For example, by naming a keyboard `seat1.keyboard` and a monitor `seat1.monitor`, you gain the ability to refer to that set of peripherals as `seat1`, which is useful if you have more than one keyboard or monitor in the physical network. As another example, naming two speakers `stereo1.left` and `stereo1.right` allows you not only to name the pair as `stereo1`, but also to disambiguate between otherwise identical speakers.

Names are unique. If an arbitrary number of peripherals may reasonably be part of a single device, e.g. a group of speakers for broadcast, they should be disambiguated with trailing numbers, e.g.: `broadsound1.speakerN`.


### Usage

#### As a user

Run `hw` or `hw list` to view the list of named peripherals, along with a list of connected but unnamed ones, and their respective status and type. `hw list <glob>` can be used to filter by name, and `hw list unnamed` to list unnamed peripherals only. For example, to check the status of peripherals connected to the first seat, use `hw list seat1.*`.

To provide a name to a peripheral, use `hw add <name>` and then connect the right peripheral. If you make a mistake, use `hw del <name>` to remove the assignment and try again. If you already know the network name (or side) of the peripheral, use `hw add <name> <side>`. Note that [`getty`](../getty) interprets the `default` side in a special manner, and the two-argument form of `hw add` is the only way to assign it a name.

After assigning the correct names, you should be able to invoke programs with the corresponding device name. For example, you can run a shell on the first seat with `getty seat1 shell`, or (supposedly, if you have a corresponding program) play music on a stereo system with `play stereo1 <file>`.


#### As a developer

The `hardware` library exports the following API:

- `hardware.resolve(name)`: translate a human-readable peripheral name (e.g. `seat1.keyboard`) to a raw peripheral name (e.g. `keyboard_1`). If the name is not assigned to any peripheral, returns `nil`.
- `hardware.wrap(name)`: a short-cut for `peripheral.wrap(hardware.resolve(name))`. Returns `nil` if the name is undefined or mapped to a disconnected peripheral.
- `hardware.resolveGroup(group_name)`: given the name of the device (e.g. `stereo1`), returns a table mapping subnames to peripheral names (e.g. `left` to `speaker_1`). Returns an empty table if no peripherals match.
- `hardware.wrapGroup(group_name)`: given the name of the device, returns a table mapping subnames to wrapped peripherals. Returns an empty table if no peripherals match.
- `hardware.set(name, native_name)`: assigns a peripheral to a name. If `native_name` is `nil`, the name is freed. Errors if the name is not a valid name.
- `hardware.listAll()`: get the table mapping names to peripheral names.
