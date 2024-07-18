#include <stdio.h>
#include <time.h>


main()
{
int rc;
struct timespec res;

  rc = clock_getres(CLOCK_MONOTONIC, &res);
  if (!rc)
    printf("CLOCK_MONOTONIC: %ldns\n", res.tv_nsec); 
  rc = clock_getres(CLOCK_MONOTONIC_COARSE, &res);
  if (!rc)
    printf("CLOCK_MONOTONIC_COARSE: %ldns\n", res.tv_nsec); 
}
