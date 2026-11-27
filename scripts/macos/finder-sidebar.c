// Finder sidebar favorites through the LSSharedFileList API (deprecated, still working on macOS 26).
// Plain C: the API's position markers are not real objects, and Swift crashes retaining them.
//   finder-sidebar list          print the favorites, one path per line
//   finder-sidebar set PATH...   replace the favorites with PATH..., in that order
// Build: clang -framework CoreServices -framework CoreFoundation -o finder-sidebar finder-sidebar.c
#include <CoreServices/CoreServices.h>
#include <stdio.h>
#include <string.h>
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void each(LSSharedFileListRef list, int remove) {
    UInt32 seed;
    CFArrayRef items = LSSharedFileListCopySnapshot(list, &seed);
    for (CFIndex i = 0; items && i < CFArrayGetCount(items); i++) {
        LSSharedFileListItemRef item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
        if (remove) {
            LSSharedFileListItemRemove(list, item);
            continue;
        }
        CFURLRef url = LSSharedFileListItemCopyResolvedURL(item, 0, NULL);
        char path[PATH_MAX] = "?";
        if (url) {
            CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof path);
            CFRelease(url);
        }
        puts(path);
    }
    if (items) CFRelease(items);
}

int main(int argc, char **argv) {
    LSSharedFileListRef list = LSSharedFileListCreate(NULL, kLSSharedFileListFavoriteItems, NULL);
    if (!list) { fputs("cannot open the Finder favorites list\n", stderr); return 1; }
    if (argc < 2 || strcmp(argv[1], "list") == 0) { each(list, 0); return 0; }
    if (strcmp(argv[1], "set") != 0) { fputs("usage: finder-sidebar list | set PATH...\n", stderr); return 2; }
    each(list, 1);
    int rc = 0;
    for (int i = 2; i < argc; i++) {
        CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)argv[i], strlen(argv[i]), true);
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast, NULL, NULL, url, NULL, NULL);
        if (item) CFRelease(item); else { fprintf(stderr, "could not add %s\n", argv[i]); rc = 1; }
        CFRelease(url);
    }
    CFRelease(list);
    return rc;
}
