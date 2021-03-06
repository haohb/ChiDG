module precon_ILU0
#include <messenger.h>
    use mod_kinds,              only: rk, ik
    use mod_constants,          only: DIAG, XI_MIN, ETA_MIN, ZETA_MIN, XI_MAX, ETA_MAX, ZETA_MAX, ONE
    use mod_inv,                only: inv
    use mod_chidg_mpi,          only: IRANK
    use mod_io,                 only: verbosity

    use type_preconditioner,    only: preconditioner_t
    use type_chidg_data,        only: chidg_data_t
    use type_chidg_matrix,      only: chidg_matrix_t
    use type_chidg_vector,      only: chidg_vector_t
    implicit none


    !>  ILU0 preconditioner
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/24/2016
    !!
    !!
    !-------------------------------------------------------------------------------------------
    type, extends(preconditioner_t) :: precon_ILU0_t

        type(chidg_matrix_t)     :: LD

    contains
    
        procedure   :: init
        procedure   :: update
        procedure   :: apply

        procedure   :: restrict

    end type precon_ILU0_t
    !*******************************************************************************************




contains



    !>  Initialize the ILU0 preconditioner. This is for allocating storage. In this case, 
    !!  we allocate a Lower-Diagonal block matrix for storing the LU decomposition.
    !!  
    !!  @author Nathan A. Wukie
    !!  @date   2/24/2016
    !!
    !!  @param[inout]   domain  domain_t instance containing a mesh component used to 
    !!                          initialize the block matrix
    !!
    !-------------------------------------------------------------------------------------------
    subroutine init(self,data)
        class(precon_ILU0_t),    intent(inout)   :: self
        type(chidg_data_t),         intent(in)      :: data


        call self%LD%init(mesh=data%mesh, mtype='LowerDiagonal')
        call self%LD%clear()

        self%initialized = .true.


    end subroutine init
    !*******************************************************************************************








    !>  Compute the block diagonal inversion and store so it can be applied.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/24/2016
    !!
    !!  Updated for spectral time integrators
    !!
    !!  @author Mayank Sharma + Nathan Wukie
    !!  @date   10/09/2017
    !!
    !-------------------------------------------------------------------------------------------
    subroutine update(self,A,b)
        class(precon_ILU0_t),    intent(inout)   :: self
        type(chidg_matrix_t),        intent(in)      :: A
        type(chidg_vector_t),        intent(in)      :: b


        integer(ik) :: idom, ielem, itime, idiagA, idiagLD, irow, icol, &
                       eparent_l, ilowerA, ilowerLD, itranspose, dparent_g_lower, &
                       eparent_g_lower, new_mat


        call write_line(' Computing ILU0 factorization', io_proc=GLOBAL_MASTER, silence=(verbosity<5))

        new_mat = self%LD%dom(1)%lblks(2,1)%loc(1,2)

        !
        ! Test preconditioner initialization
        !
        if ( .not. self%initialized ) call chidg_signal(FATAL,'ILU0%update: preconditioner has not yet been initialized.')

       
        do itime = 1,size(A%dom(1)%lblks,2)
        
            !
            ! For each domain
            !
            do idom = 1,size(A%dom)



                !
                ! Store diagonal blocks of A
                !
                do ielem = 1,size(A%dom(idom)%lblks,1)
                    !do itime = 1,size(A%dom(idom)%lblks,2)

                        idiagA = A%dom(idom)%lblks(ielem,itime)%get_diagonal()
                        idiagLD = self%LD%dom(idom)%lblks(ielem,itime)%get_diagonal()

                        self%LD%dom(idom)%lblks(ielem,itime)%data_(idiagLD)%mat = A%dom(idom)%lblks(ielem,itime)%data_(idiagA)%mat

                    !end do !itime
                end do !ielem


                !
                ! Invert first diagonal block
                !
                !idiagLD = self%LD%dom(idom)%lblks(1,1)%get_diagonal()
                !self%LD%dom(idom)%lblks(1,1)%data_(idiagLD)%mat = inv(self%LD%dom(idom)%lblks(1,1)%data_(idiagLD)%mat)
                idiagLD = self%LD%dom(idom)%lblks(1,itime)%get_diagonal()
                self%LD%dom(idom)%lblks(1,itime)%data_(idiagLD)%mat = inv(self%LD%dom(idom)%lblks(1,itime)%data_(idiagLD)%mat)



                !
                ! Loop through all Proc-Local rows
                !
                !itime = 1
                do irow = 2,size(A%dom(idom)%lblks,1)


                    !
                    ! Operate on all the L blocks for the current row
                    !
                    do icol = 1,A%dom(idom)%local_lower_blocks(irow,itime)%size()

                        ilowerA = A%dom(idom)%local_lower_blocks(irow,itime)%at(icol)

                        dparent_g_lower = A%dom(idom)%lblks(irow,itime)%dparent_g(ilowerA)
                        eparent_g_lower = A%dom(idom)%lblks(irow,itime)%eparent_g(ilowerA)

                        ilowerLD = self%LD%dom(idom)%lblks(irow,itime)%loc(dparent_g_lower,eparent_g_lower)

                        if (A%dom(idom)%lblks(irow,itime)%parent_proc(ilowerA) == IRANK) then

                            ! Get parent index
                            eparent_l = A%dom(idom)%lblks(irow,itime)%eparent_l(ilowerA)

                            ! Get diagonal entry
                            idiagLD = self%LD%dom(idom)%lblks(eparent_l,itime)%get_diagonal()

                            ! Compute and store the contribution to the lower-triangular part of LD
                            self%LD%dom(idom)%lblks(irow,itime)%data_(ilowerLD)%mat = matmul(A%dom(idom)%lblks(irow,itime)%data_(ilowerA)%mat,self%LD%dom(idom)%lblks(eparent_l,itime)%data_(idiagLD)%mat)

                            ! Modify the current diagonal by this lower-triangular part multiplied by opposite upper-triangular part. (The component in the transposed position)
                            itranspose = A%dom(idom)%lblks(irow,itime)%itranspose(ilowerA)
                            idiagLD = self%LD%dom(idom)%lblks(irow,itime)%get_diagonal()

                            ! Compute and store the contribution to the lower-triangular part of LD
                            self%LD%dom(idom)%lblks(irow,itime)%data_(idiagLD)%mat = self%LD%dom(idom)%lblks(irow,itime)%data_(idiagLD)%mat  -  &
                                     matmul(self%LD%dom(idom)%lblks(irow,itime)%data_(ilowerLD)%mat,  A%dom(idom)%lblks(eparent_l,itime)%data_(itranspose)%mat)

                        end if

                    end do ! icol


                    !
                    ! Pre-Invert current diagonal block and store
                    !
                    idiagLD = self%LD%dom(idom)%lblks(irow,itime)%get_diagonal()
                    self%LD%dom(idom)%lblks(irow,itime)%data_(idiagLD)%mat = inv(self%LD%dom(idom)%lblks(irow,itime)%data_(idiagLD)%mat)




                end do !irow



            end do ! idom

        end do  ! itime

        call write_line(' Done Computing ILU0 factorization', io_proc=GLOBAL_MASTER, silence=(verbosity<5))


    end subroutine update
    !*******************************************************************************************








    !> Apply the preconditioner to the krylov vector 'v' and return preconditioned vector 'z'
    !!
    !!  @author Nathan A. Wukie
    !!  @date   2/24/2016
    !!
    !!  Updated for spectral time integrators
    !!
    !!  @author Mayank Sharma + Nathan Wukie
    !!  @date   10/09/2017
    !!
    !-------------------------------------------------------------------------------------------
    function apply(self,A,v) result(z)
        class(precon_ILU0_t),   intent(inout)   :: self
        type(chidg_matrix_t),    intent(in)      :: A
        type(chidg_vector_t),    intent(in)      :: v

        type(chidg_vector_t)         :: z

        integer(ik)             :: ielem, itime, idiag, eparent_l, idom, irow, icol, &
                                   ilowerA, ilowerLD, iupper, dparent_g_lower, eparent_g_lower, &
                                   inner_time, precon_ntime
        real(rk),   allocatable :: temp(:)


        call self%timer%start()


        !
        ! Initialize z for preconditioning
        !
        z = v

        !
        ! Set ntime for preconditioner computations
        ! TODO: Can also be set using time manager data
        !
        precon_ntime = z%get_ntime()


        do itime = 1,precon_ntime


            !
            ! For each domain
            !
            do idom = 1,size(A%dom)


                !
                ! Forward Solve - Local
                !
                !itime = 1
                do irow = 1,size(self%LD%dom(idom)%lblks,1)


                    !
                    ! Lower-Triangular blocks
                    !
                    do icol = 1,A%dom(idom)%local_lower_blocks(irow,itime)%size()

                        ilowerA = A%dom(idom)%local_lower_blocks(irow,itime)%at(icol)

                        dparent_g_lower = A%dom(idom)%lblks(irow,itime)%dparent_g(ilowerA)
                        eparent_g_lower = A%dom(idom)%lblks(irow,itime)%eparent_g(ilowerA)
                        
                        ilowerLD = self%LD%dom(idom)%lblks(irow,itime)%loc(dparent_g_lower,eparent_g_lower)

                        if ( A%dom(idom)%lblks(irow,itime)%parent_proc(ilowerA) == IRANK ) then
                                
                                ! Get associated parent block index
                                eparent_l = self%LD%dom(idom)%lblks(irow,itime)%eparent_l(ilowerLD)
                                !z%dom(idom)%vecs(irow)%vec = z%dom(idom)%vecs(irow)%vec - matmul(self%LD%dom(idom)%lblks(irow,itime)%data_(ilowerLD)%mat, z%dom(idom)%vecs(eparent_l)%vec)

                                if (allocated(temp)) deallocate(temp)
                                allocate(temp(size(z%dom(idom)%vecs(irow)%gettime(itime))))

                                temp = z%dom(idom)%vecs(irow)%gettime(itime) - matmul(self%LD%dom(idom)%lblks(irow,itime)%data_(ilowerLD)%mat, z%dom(idom)%vecs(eparent_l)%gettime(itime))
                                call z%dom(idom)%vecs(irow)%settime(itime,temp)

                        end if


                    end do


                end do ! irow




                !
                ! Backward Solve
                !
                do irow = size(A%dom(idom)%lblks,1),1,-1

                    !
                    ! Upper-Triangular blocks
                    !
                    do icol = 1,A%dom(idom)%local_upper_blocks(irow,itime)%size()

                        iupper = A%dom(idom)%local_upper_blocks(irow,itime)%at(icol)

                        if (A%dom(idom)%lblks(irow,itime)%parent_proc(iupper) == IRANK) then

                                ! Get associated parent block index
                                eparent_l = A%dom(idom)%lblks(irow,itime)%eparent_l(iupper)
                                !z%dom(idom)%vecs(irow)%vec = z%dom(idom)%vecs(irow)%vec - matmul(A%dom(idom)%lblks(irow,itime)%data_(iupper)%mat, z%dom(idom)%vecs(eparent_l)%vec)

                                if (allocated(temp)) deallocate(temp)
                                allocate(temp(size(z%dom(idom)%vecs(irow)%gettime(itime))))

                                temp = z%dom(idom)%vecs(irow)%gettime(itime) - matmul(A%dom(idom)%lblks(irow,itime)%data_(iupper)%mat, z%dom(idom)%vecs(eparent_l)%gettime(itime))
                                call z%dom(idom)%vecs(irow)%settime(itime,temp)

                        end if


                    end do


                    !
                    ! Diagonal block
                    !
                    idiag = self%LD%dom(idom)%lblks(irow,itime)%get_diagonal()
                    !z%dom(idom)%vecs(irow)%vec = matmul(self%LD%dom(idom)%lblks(irow,itime)%data_(idiag)%mat, z%dom(idom)%vecs(irow)%vec)
                    
                    if (allocated(temp)) deallocate(temp)
                    allocate(temp(size(z%dom(idom)%vecs(irow)%gettime(itime))))

                    temp = matmul(self%LD%dom(idom)%lblks(irow,itime)%data_(idiag)%mat, z%dom(idom)%vecs(irow)%gettime(itime))
                    call z%dom(idom)%vecs(irow)%settime(itime,temp)


                end do ! irow




            end do ! idom

        end do ! itime



        call self%timer%stop()

    end function apply
    !-----------------------------------------------------------------------------------------








    !>  Produce a restricted version of the current preconditioner.
    !!
    !!  @author Nathan A. Wukie
    !!  @date   7/24/2017
    !!
    !!
    !-----------------------------------------------------------------------------------------
    function restrict(self,nterms_r) result(restricted)
        class(precon_ILU0_t),   intent(in)  :: self
        integer(ik),            intent(in)  :: nterms_r

        type(precon_ILU0_t) :: restricted

        restricted%LD = self%LD%restrict(nterms_r)
        restricted%initialized = .true.

    end function restrict
    !****************************************************************************************









end module precon_ILU0
