/* The check for engine/patches/winecx-ntdll-msync-alert-fd.patch, built with mingw and run under
 * Wine with WINEMSYNC=1 by .github/workflows/enginefix.yml: threads that wait alertably and then
 * end must leave the process's files alone. Before the fix every such thread closed, as it ended,
 * the Unix file whose number matched its msync alert object, so files opened before broke: a read
 * failed, or – the number taken again by a pipe meanwhile – waited forever. Prints "ok" and exits
 * 0, or says which file broke and exits 1. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define FILES 1000
#define THREADS 1000

static HANDLE files[FILES];
static int broken = -1;
static DWORD broken_error;

static DWORD WINAPI worker( void *arg )
{
    SleepEx( 1, TRUE );  /* an alertable wait: the thread gets its alert object */
    return 0;
}

static DWORD WINAPI check_files( void *arg )
{
    for (int i = 0; i < FILES; i++)
    {
        char buffer[16] = {0};
        DWORD done = 0;
        SetFilePointer( files[i], 0, NULL, FILE_BEGIN );
        if (!ReadFile( files[i], buffer, 10, &done, NULL ) || done != 10 || memcmp( buffer, "nightforge", 10 ))
        {
            broken = i;
            broken_error = GetLastError();
            return 1;
        }
    }
    return 0;
}

int main( void )
{
    char folder[MAX_PATH], name[MAX_PATH + 64];
    DWORD done;
    HANDLE checker;

    GetTempPathA( sizeof(folder), folder );
    for (int i = 0; i < FILES; i++)
    {
        snprintf( name, sizeof(name), "%snightforge-probe-%lu-%d.txt", folder, GetCurrentProcessId(), i );
        files[i] = CreateFileA( name, GENERIC_READ | GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                                FILE_FLAG_DELETE_ON_CLOSE, NULL );
        /* Writing makes Wine hand the process the file's Unix descriptor, which it keeps. */
        if (files[i] == INVALID_HANDLE_VALUE || !WriteFile( files[i], "nightforge", 10, &done, NULL ))
        {
            printf( "can't set up file %d (error %lu)\n", i, GetLastError() );
            return 2;
        }
    }
    for (int i = 0; i < THREADS; i++)
    {
        HANDLE thread = CreateThread( NULL, 0, worker, NULL, 0, NULL );
        if (!thread)
        {
            printf( "can't start thread %d (error %lu)\n", i, GetLastError() );
            return 2;
        }
        WaitForSingleObject( thread, INFINITE );
        CloseHandle( thread );
    }
    /* In a thread of its own, so a read that waits forever ends as a failure, not a hang. */
    checker = CreateThread( NULL, 0, check_files, NULL, 0, NULL );
    if (WaitForSingleObject( checker, 30000 ) == WAIT_TIMEOUT)
    {
        printf( "reading the files hangs after %d threads ended\n", THREADS );
        fflush( stdout );
        ExitProcess( 1 );
    }
    if (broken >= 0)
    {
        printf( "file %d of %d broke after %d threads ended (error %lu)\n", broken, FILES, THREADS, broken_error );
        return 1;
    }
    printf( "ok: %d files intact after %d threads ended\n", FILES, THREADS );
    return 0;
}
