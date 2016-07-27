module type_RASILU0_recv_dom_comm
#include <messenger.h>
    use mod_kinds,                          only: rk, ik
    use mod_constants,                      only: DIAG
    use mod_chidg_mpi,                      only: ChiDG_COMM, IRANK

    use type_RASILU0_recv_dom_comm_elem,    only: RASILU0_recv_dom_comm_elem_t
    use type_mesh,                          only: mesh_t
    use type_blockmatrix,                   only: blockmatrix_t

    use mpi_f08,    only: MPI_Recv, MPI_INTEGER4, MPI_STATUS_IGNORE, MPI_ANY_TAG
    implicit none





    !>
    !!
    !!  @author Nathan A. Wukie (AFRL)
    !!  @date   7/21/2016
    !!
    !!
    !-----------------------------------------------------------------------------------------
    type, public :: RASILU0_recv_dom_comm_t

        integer(ik)                                     :: proc
        type(RASILU0_recv_dom_comm_elem_t), allocatable :: elem(:)     ! For each overlapping element coming from a processor, a container storing the linearization blocks being communicated

    contains
        
        procedure   :: init

    end type RASILU0_recv_dom_comm_t
    !*****************************************************************************************





contains





    !>
    !!
    !!  @author Nathan A. Wukie (AFRL)
    !!  @date   7/21/2016
    !!
    !!
    !!
    !----------------------------------------------------------------------------------------
    subroutine init(self,mesh,a,proc)
        class(RASILU0_recv_dom_comm_t), intent(inout)   :: self
        type(mesh_t),                   intent(in)      :: mesh
        type(blockmatrix_t),            intent(in)      :: a
        integer(ik),                    intent(in)      :: proc

        integer(ik)                 :: ielem_recv, nelem_recv, nblk_recv, idomain_g, iblk, ierr
        integer(ik)                 :: nrows, ncols, dparent_g, dparent_l, eparent_g, eparent_l, parent_proc
        integer(ik)                 :: iblk_diag, iblk_recv, parent_proc_diag, parent_proc_offdiag_loop
        integer(ik)                 :: ielem_loop, iblk_loop, eparent_l_diag, eparent_l_diag_loop, eparent_l_offdiag_loop, iblk_diag_loop
        integer(ik)                 :: eparent_g_diag, eparent_g_diag_loop, eparent_g_offdiag_loop, test_elem, test_blk
        integer(ik)                 :: block_data(7)
        integer(ik), allocatable    :: blk_indices(:)
        logical                     :: lower_block, upper_block, overlap_element, transpose_found

        self%proc = proc


        !
        ! Get global index of the local domain
        !
        idomain_g = mesh%idomain_g


        !
        ! Get number of neighbor(overlapping) elements being received from proc for idomain_g
        !
        call MPI_Recv(nelem_recv, 1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)



        allocate(self%elem(nelem_recv), stat=ierr)
        if (ierr /= 0) call AllocationError



        !
        ! Receive element data
        !
        do ielem_recv = 1,nelem_recv

            !
            ! Get number of blocks that are being received for the element
            !
            call MPI_Recv(nblk_recv, 1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)

            ! Initialize element row with the number of blocks being received
            call self%elem(ielem_recv)%init(nblk_recv)


            !
            ! Get the block indices
            !
            if (allocated(blk_indices)) deallocate(blk_indices)
            allocate(blk_indices(nblk_recv), stat=ierr)
            if (ierr /= 0) call AllocationError

            call MPI_Recv(self%elem(ielem_recv)%blk_indices, nblk_recv, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)


            !
            ! Receive matrix blocks
            !
            do iblk = 1,nblk_recv

                ! Receive block integer data
                call MPI_Recv(nrows,       1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)
                call MPI_Recv(ncols,       1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)
                call MPI_Recv(dparent_g,   1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)
                call MPI_Recv(dparent_l,   1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)
                call MPI_Recv(eparent_g,   1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)
                call MPI_Recv(eparent_l,   1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)
                call MPI_Recv(parent_proc, 1, MPI_INTEGER4, proc, idomain_g, ChiDG_COMM, MPI_STATUS_IGNORE, ierr)

                if (eparent_g == 0) call chidg_signal(FATAL, "RASILU0_recv_dom_comm: bad element index received in initialization")

                ! Initialize densematrix
                if ( (nrows == 0) .or. (ncols == 0) ) call chidg_signal(FATAL, "nrows/ncols == 0")
                call self%elem(ielem_recv)%blks(iblk)%init(nrows,ncols,dparent_g,dparent_l,eparent_g,eparent_l,parent_proc)


            end do !iblk


        end do ! ielem_recv









        !
        ! Find diagonal block
        !
        do ielem_recv = 1,size(self%elem)

            nblk_recv = size(self%elem(ielem_recv)%blks)

            !do iblk_recv = 1,nblk_recv
            do iblk_recv = 1,size(self%elem(ielem_recv)%blks)
                iblk = self%elem(ielem_recv)%blk_indices(iblk_recv)

                if (iblk == DIAG) call self%elem(ielem_recv)%diag%push_back(iblk_recv)

            end do !iblk
            if (self%elem(ielem_recv)%diag%size() /= 1) call chidg_signal(FATAL,"RASILU0_recv_dom_comm%init: Number of diagonal blocks is not equal to one")

        end do !ielem_recv





        do ielem_recv = 1,size(self%elem)

            iblk_diag        = self%elem(ielem_recv)%diag%at(1)
            eparent_g_diag   = self%elem(ielem_recv)%blks(iblk_diag)%eparent_g()
            eparent_l_diag   = self%elem(ielem_recv)%blks(iblk_diag)%eparent_l()
            parent_proc_diag = self%elem(ielem_recv)%blks(iblk_diag)%parent_proc()


            !
            ! Find lower/upper blocks
            !
            !do iblk_recv = 1,nblk_recv
            do iblk_recv = 1,size(self%elem(ielem_recv)%blks)
                if ( iblk_recv /= iblk_diag ) then

                    parent_proc = self%elem(ielem_recv)%blks(iblk_recv)%parent_proc()
                    
                    overlap_element = (parent_proc == parent_proc_diag)

                    if ( overlap_element ) then
                        ! Off-diagonal block is associated with element on the same proc as the diagonal element.
                        ! So, they are coupled with each other in the overlap layer
                        eparent_l = self%elem(ielem_recv)%blks(iblk_recv)%eparent_l()

                        lower_block = (eparent_l < eparent_l_diag)
                        upper_block = (eparent_l > eparent_l_diag)

                        if (lower_block) call self%elem(ielem_recv)%lower%push_back(iblk_recv)
                        if (upper_block) call self%elem(ielem_recv)%upper%push_back(iblk_recv)
        

                    else
                        ! Off-diagonal block is associated with element on the recv proc. These are all set to lower blocks 
                        ! since the recv elements are put at the end of the matrix diagonal.
                        call self%elem(ielem_recv)%lower%push_back(iblk_recv)

                    end if



                end if
            end do !iblk_recv









            !
            ! Find transposed block
            !
            self%elem(ielem_recv)%trans_elem = 0
            self%elem(ielem_recv)%trans_blk = 0
            !do iblk_recv = 1,nblk_recv
            do iblk_recv = 1,size(self%elem(ielem_recv)%blks)

                transpose_found = .false.
    
                !
                ! Transpose of block diagonal
                !
                if ( iblk_recv == iblk_diag ) then
                    self%elem(ielem_recv)%trans_elem(iblk_recv) = ielem_recv
                    self%elem(ielem_recv)%trans_blk(iblk_recv)  = iblk_diag
                    transpose_found = .true.

                else


                    eparent_g   = self%elem(ielem_recv)%blks(iblk_recv)%eparent_g()
                    eparent_l   = self%elem(ielem_recv)%blks(iblk_recv)%eparent_l()
                    parent_proc = self%elem(ielem_recv)%blks(iblk_recv)%parent_proc()


                    !
                    ! Transpose of blocks coupled with the interior
                    !
                    if ( parent_proc == IRANK ) then

                        ! Off-diagonal block is associated with element on the recv proc.
                        do iblk_loop = 1,size(a%lblks,2)
                            if ( allocated(a%lblks(eparent_l,iblk_loop)%mat) ) then
                                eparent_g_offdiag_loop   = a%lblks(eparent_l,iblk_loop)%eparent_g()
                                eparent_l_offdiag_loop   = a%lblks(eparent_l,iblk_loop)%eparent_l()
                                parent_proc_offdiag_loop = a%lblks(eparent_l,iblk_loop)%parent_proc()


                                transpose_found = ( (eparent_g_offdiag_loop == eparent_g_diag) .and. (parent_proc_offdiag_loop == parent_proc_diag) )
                                if (transpose_found) then
                                    self%elem(ielem_recv)%trans_elem(iblk_recv) = eparent_l
                                    self%elem(ielem_recv)%trans_blk(iblk_recv)  = iblk_loop
                                    exit
                                end if
                            end if
                        end do !iblk_loop

                        if ( .not. transpose_found ) call chidg_signal(FATAL, "No transposed block found for RASILU0 recv block")


                    !
                    ! Transpose of blocks coupled with other overlap elements
                    !
                    else

                        ! Off-diagonal block is associated with element on the same proc as the diagonal element.
                        ! So, they are coupled with each other in the overlap layer

                        do ielem_loop = 1,size(self%elem)                        
                            iblk_diag_loop      = self%elem(ielem_loop)%diag%at(1)
                            eparent_g_diag_loop = self%elem(ielem_loop)%blks(iblk_diag_loop)%eparent_g()
                            eparent_l_diag_loop = self%elem(ielem_loop)%blks(iblk_diag_loop)%eparent_l()


                            if (eparent_g == eparent_g_diag_loop) then
                                do iblk_loop = 1,size(self%elem(ielem_loop)%blks)

                                    eparent_g_offdiag_loop   = self%elem(ielem_loop)%blks(iblk_loop)%eparent_g()
                                    eparent_l_offdiag_loop   = self%elem(ielem_loop)%blks(iblk_loop)%eparent_l()
                                    parent_proc_offdiag_loop = self%elem(ielem_loop)%blks(iblk_loop)%parent_proc()

                                    transpose_found = ( (eparent_g_offdiag_loop == eparent_g_diag) .and. (parent_proc_offdiag_loop == parent_proc_diag) )
                                    if (transpose_found) then
                                        self%elem(ielem_recv)%trans_elem(iblk_recv) = ielem_loop
                                        self%elem(ielem_recv)%trans_blk(iblk_recv)  = iblk_loop
                                        exit
                                    end if
                                end do !iblk_loop
                            end if

                            if (transpose_found) exit

                        end do !ielem_loop
                        if ( .not. transpose_found ) call chidg_signal(FATAL, "No transposed block found for RASILU0 overlap block")




                    end if



                end if



            end do !iblk_recv


        end do !ielem_recv



    end subroutine init
    !*****************************************************************************************










end module type_RASILU0_recv_dom_comm
