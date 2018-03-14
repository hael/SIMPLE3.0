#define _GNU_SOURCE             /* See feature_test_macros(7) */
#include <sys/types.h>
#include <sys/stat.h>
#include<stdio.h>
#include<stdlib.h>
#include<unistd.h>
#include<string.h>
#include<sys/wait.h>
#include<errno.h>
#include<pwd.h>

#ifdef __linux__
#include<linux/limits.h>
#endif


#include <dirent.h>
#include <stdio.h>
#include <string.h>

#define NORMAL_COLOR  "\x1B[0m"
#define GREEN  "\x1B[32m"
#define BLUE  "\x1B[34m"

#include <sys/stat.h>
#include <sys/types.h>

#define MAKEDIR makedir_
int makedir(const char *pathname){
  mode_t mask = umask(0777);
  umask(mask);
  return mkdir(pathname, mask);
}

/* let us make a recursive function to print the content of a given folder */
char ** file_list;
void show_dir_content(const char * path)
{
  DIR * d = opendir(path); // open the path
  if(d==NULL) return; // if was not able return
  struct dirent * dir; // for the directory entries
  while ((dir = readdir(d)) != NULL) // if we were able to read somehting from the directory
    {
      if(dir-> d_type != DT_DIR) // if the type is not directory just print it with blue
        printf("%s%s\n",BLUE, dir->d_name);
      else
      if(dir -> d_type == DT_DIR && strcmp(dir->d_name,".")!=0 && strcmp(dir->d_name,"..")!=0 ) // if it is a directory
      {
        printf("%s%s\n",GREEN, dir->d_name); // print its name in green
        char d_path[255]; // here I am using sprintf which is safer than strcat
        sprintf(d_path, "%s/%s", path, dir->d_name);
        show_dir_content(d_path); // recall with the new path
      }
    }
    closedir(d); // finally close the directory
}

int get_file_list(const char * path, char ** results_files, char** results_dirs)
{
  DIR           *d;
  struct dirent *elem;
  d = opendir(path);
  if (d)
  {
    while ((elem = readdir(d)) != NULL)
    {
      printf("%s\n", elem->d_name);
    }

    closedir(d);
  }

  return(0);
}



char *F90toCstring(char *str,int len)
{
  char *res; /* C arrays are from 0:len-1 */
  if((res=(char*)malloc(len+1)))
    {
      strncpy(res,str,len);
      res[len]='\0';
    }
  return res;
}


void fortran_rmdir_(char *buf, int *status,int buflength)
{
  char *buffer;
  extern int errno;

  *status=-1;

  if(!(buffer=F90toCstring(buf,buflength)))
    {
      perror("Failed : appendtostring (buf) in posixwrapper:fortranrmdir");
      exit(1);
    }

  errno=0;
  *status=rmdir(buffer);

  if(*status==-1)
    {
      printf("%d %s\n",errno,strerror(errno));
      perror("Failed : rmdir in posixwrapper:fortranrmdir");
      exit(1);
    }

  *status=0;
  free(buffer);
}
