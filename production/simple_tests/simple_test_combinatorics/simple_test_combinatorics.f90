program simple_test_combinatorics
use simple_combinatorics, only: diverse_labeling
implicit none
integer, allocatable :: configs_diverse(:,:)
configs_diverse = diverse_labeling(50000, 5, 20)

! print *, configs_diverse(1,:)
! print *, '****************'
! print *, configs_diverse(2,:)
! print *, '****************'
! print *, configs_diverse(3,:)
! print *, '****************'
! print *, configs_diverse(4,:)
! print *, '****************'
! print *, configs_diverse(5,:)


end program simple_test_combinatorics