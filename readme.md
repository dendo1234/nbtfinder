# NBTFinder
NBTFinder is a CLI app for searching strings in minecraft's NBT files.

## usage
Running the executable in the command line should print the available options.

In general, this is a quite specialized tool. I recommend using this if you need to bulk
search in a entire world. Say you want to find which chunk has a rare block or a man made block,
you can set the pattern argument to the block's name and search the world's region folder
with the find_first procedure. The program will return the first chunk in each file that matched the pattern,
narrowing down the search. Then, you can use your favorite NBT tool to complete the search and 
find the exact block coordinate of the desired block.

It doesn't actually interpret the NBT files. It just handles the decompression and search
the uncompressed NBT if they were just a big string buffer. The results of count_all aren't the amount of
*blocks*, is just the amount of strings matches, this happens because of the NBT chunk pallet mechanism.

## performance

It has multithread capabilities, so it can search multiple files at the same time. 

For a Ryzen 5 7600, with 12 threads, one can expect this output:

```
> nbtfinder.exe region diamond count_all
Found at C:\Users\dendo\AppData\Roaming\PrismLauncher\instances\terrafirmagreg 2\minecraft\saves\FNAF_World\region\r.-1.2.mca, count: 136
Found at C:\Users\dendo\AppData\Roaming\PrismLauncher\instances\terrafirmagreg 2\minecraft\saves\FNAF_World\region\r.-1.11.mca, count: 65

... 

Found at C:\Users\dendo\AppData\Roaming\PrismLauncher\instances\terrafirmagreg 2\minecraft\saves\FNAF_World\region\r.5.1.mca, count: 197
Found at C:\Users\dendo\AppData\Roaming\PrismLauncher\instances\terrafirmagreg 2\minecraft\saves\FNAF_World\region\r.6.0.mca, count: 134
Proccessed (total|speed): compressed:1.75GiB|696.99MiB/s, uncompressed:8.32GiB|3.24GiB/s, time:2.5669993s
Finished
```

So it has decent enough speed to search an entire world in just a few seconds.

The implemented functions for searching the desired strings are pretty naive, but, for region files, around 70% of the time is spent on the 
Odin's zlib library plus 10% of buffer copies, so it shouldn't be much of a concern. 
If you are a decompression wizard, you might be able to push this to run much faster.

## lore

Once upon a time, one was playing the amazing terrafirmagreg modpack. This one person happens to make and place all of the expensive new machines in a single crate.
But then, this person (which most definitely is me) lost the crate, and all of the dozen of hours of work making the machines would be in vain if the crate remained lost.
So, not wanting to cheat, one would spent a ton of time in search for the missing crate, resorting even to search in the game files themselves. But the slow NBT tools they
knew were, in fact, too slow to handle a multi gigabyte sized world. So they were set into making making a fast alternative.

Seriously though, when I started doing this, it had a way bigger scope, but, during the research I've learned of the many amazing NBT manipulation tools that exists out there, so
there wasn't too much point into "reinventing the wheel". So I narrowed the scope to just the file searching part (which is a very lacking feature in many tools) before I went insane
writing UI code. This is my first Odin project and my first time using Clay for real, which is a problem, as I got deeper into the project, the more I felt rewriting the old code as
I gained more knowledge.

In the end, I didn't found the crate. I've some guess about what happened: I had to delete a ticking block entity to resolve a crash, and I've realized that, in the process, an
ore create in the same chunk lost all of its items, probably an error on the NBT tool I've used for that, so I think the machine crate probably got its contents deleted that way.
Since it was a bug, I ended up getting the lost machines in creative by memory. Some time later, one of the cheated machines exploded due to bad wiring, destroying nearby ones. 
When I got to craft a replacement, I've realized that hadn't crafted it originally, so the greg gods punished me by taking some other machines in the process. That's the moral of the story.

## compiling

The build.odin script at the project's root handles the compilation. Build it with

```
odin build build.odin -file
```

Then, run the created executable to build the project.

### old compile
The -old flag to the build executable can be used to build the project to its original scope.
That requires the clay git submodule to be initialized with:

```
git submodule init
git submodule update
```

The -old build link to SDL3 and its sister libraries by shared libraries included in the Odin compiler.

## thanks

Thanks to [NBTExplorer](https://github.com/jaquadro/NBTExplorer) for serving as inspiration.
Thanks to [TerraFirmaGreg](https://terrafirmagreg.team/) for giving me reason to put up with all challenges this project brought.

And thanks to you for reading though this!

