* [Overview](01_overview.md)
* [Basics](02_basics.md)
* [Introduction](03_introduction.md)
* [Credits](10_credits.md)
* [HOWTO file a BUG](11_howto_bug.md)

The whole project is licenced by [GNU Affero General Public License, Verison 3.0](https://github.com/RalphBariz/FLOW/blob/master/LICENSE) [Please read the notes in LICENCE file.]

**BUILD:**
Linux only
* For Debian and derivates please see http://d-apt.sourceforge.net/ and install `sudo apt-get install dmd-bin cmake`
* For Arch Linux and derivates `pacman -S dmd cmake`
* Clone this Git repository and cd to it's root
* `git submodule update --init`
* `./build` or 
* `cmake -DCMAKE_MODULE_PATH:PATH=$(pwd)/util/cmake-d/cmake-d && make && make test`

**RUN:**
Dependent of the project you built, its binaries are located in a subfolder *bin* or *lib*
