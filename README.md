* [Overview](https://github.com/RalphBariz/flow/blob/master/doc/overview.md)
* [Philosophy](https://github.com/RalphBariz/flow/blob/master/doc/philosophy.md)
* [Specification](https://github.com/RalphBariz/flow/blob/master/doc/specification.md)
* [Implementation guide](https://github.com/RalphBariz/flow/blob/master/doc/implementation.md)
* [Credits](https://github.com/RalphBariz/flow/blob/master/doc/credits.md)

[HOWTO file a BUG](https://github.com/RalphBariz/FLOW/blob/master/HOWTO%20BUG.md)

The whole project is licenced by [GNU General Public License, Verison 3.0](https://github.com/RalphBariz/FLOW/blob/master/LICENSE) [Please read the notes in LICENCE file.]

**BUILD:**
Linux only
* For Debian and derivates please see http://d-apt.sourceforge.net/ and install `sudo apt-get install dub dmd-bin`
* For Arch Linux `pacman -S dub dmd`
* Clone this Git repository
* `dub add-path <path of git repository>`
* `cd <what subproject you need>`
* `dub`

**RUN:**
Dependent of the project you built, its binaries are located in a subfolder *bin* or *lib*
