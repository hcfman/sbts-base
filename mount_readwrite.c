#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <pwd.h>
#include <stdio.h>


int main( int argc, char *argv[] ) {
    if ( getuid() == 0 ) {
	printf( "Do not run this command as root please" );
	exit( 1 );
    }

    char *MOUNT_COMMAND = "/bin/mount -o remount,rw,noatime,nodiratime ";
    struct passwd *pw = getpwuid(getuid());

    if ( pw == NULL ) {
	exit( 1 );
    }

    char *fullCommand = calloc( strlen( MOUNT_COMMAND ) + strlen( pw -> pw_dir ) + 1, 1 );
    strcpy( fullCommand, MOUNT_COMMAND );
    strcat( fullCommand, pw -> pw_dir );
    strcat( fullCommand, "/config" );

    setuid(0);
    execl("/bin/bash", "bash", "-c", fullCommand, NULL );
}
