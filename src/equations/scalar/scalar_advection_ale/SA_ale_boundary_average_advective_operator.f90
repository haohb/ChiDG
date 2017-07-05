module SA_ale_boundary_average_advective_operator
#include <messenger.h>
    use mod_kinds,                  only: rk,ik
    use mod_constants,              only: ZERO,ONE,TWO,HALF
    use type_operator,              only: operator_t
    use type_chidg_worker,          only: chidg_worker_t
    use type_properties,            only: properties_t
    use DNAD_D
    implicit none


    !>
    !!
    !!  @author Nathan A. Wukie
    !!
    !!
    !!
    !!
    !--------------------------------------------------------------------------------
    type, extends(operator_t), public :: SA_ale_boundary_average_advective_operator_t


    contains

        procedure   :: init
        procedure   :: compute

    end type SA_ale_boundary_average_advective_operator_t
    !********************************************************************************



contains


    !>
    !!
    !!  @author Nathan A. Wukie (AFRL)
    !!  @date   8/29/2016
    !!
    !--------------------------------------------------------------------------------
    subroutine init(self)
        class(SA_ale_boundary_average_advective_operator_t),   intent(inout)  :: self

        ! Set operator name
        call self%set_name('Scalar Advection ALE Boundary Average Operator')

        ! Set operator type
        call self%set_operator_type('Boundary Advective Operator')

        ! Set operator equations
        call self%add_primary_field('u')

    end subroutine init
    !********************************************************************************










    !> Compute the average advective boundary flux for scalar linear advection
    !!
    !!   @author Nathan A. Wukie
    !!
    !!   @param[in]      mesh    Mesh data
    !!   @param[inout]   sdata   Solver data. Solution, RHS, Linearization etc.
    !!   @param[in]      ielem   Element index
    !!   @param[in]      iface   Face index
    !!   @param[in]      iblk    Block index indicating the linearization direction
    !!
    !-----------------------------------------------------------------------------------------
    subroutine compute(self,worker,prop)
        class(SA_ale_boundary_average_advective_operator_t),    intent(inout)   :: self
        type(chidg_worker_t),                               intent(inout)   :: worker
        class(properties_t),                                intent(inout)   :: prop


        type(AD_D), allocatable, dimension(:)   ::  &
            u_m, u_p,                               &
            c1_m, c2_m, c3_m,                       &
            c1_p, c2_p, c3_p,                       &
            flux_1, flux_2, flux_3, integrand, flux_1_ref, flux_2_ref, flux_3_ref

        real(rk), allocatable, dimension(:) ::      &
           u_grid, v_grid, w_grid, det_jacobian_grid, testx


        real(rk), allocatable, dimension(:,:,:) ::      &
            jacobian_grid


        real(rk),   allocatable, dimension(:)   ::  &
            norm_1, norm_2, norm_3


 
        u_grid = worker%get_grid_velocity_face("u_grid")
        v_grid = worker%get_grid_velocity_face("v_grid")
        w_grid = worker%get_grid_velocity_face("w_grid")

!        print *, 'u_grid'
!        print *, u_grid
!        print *, 'v_grid'
!        print *, v_grid
!        print *, 'w_grid'
!        print *, w_grid
        jacobian_grid = worker%get_inv_jacobian_grid_face()
        det_jacobian_grid = worker%get_det_jacobian_grid_face()

       
        !
        ! Interpolate solution to quadrature nodes
        !
        u_m = worker%get_primary_field_face('u','value' , 'face interior')
        u_p = worker%get_primary_field_face('u','value' , 'face exterior')

        u_m = u_m/det_jacobian_grid
        u_p = u_p/det_jacobian_grid
        
        !
        ! Get model coefficients
        !
        c1_m = worker%get_model_field_face('Scalar Advection Velocity-1', 'value', 'face interior')
        c2_m = worker%get_model_field_face('Scalar Advection Velocity-2', 'value', 'face interior')
        c3_m = worker%get_model_field_face('Scalar Advection Velocity-3', 'value', 'face interior')
        c1_p = worker%get_model_field_face('Scalar Advection Velocity-1', 'value', 'face exterior')
        c2_p = worker%get_model_field_face('Scalar Advection Velocity-2', 'value', 'face exterior')
        c3_p = worker%get_model_field_face('Scalar Advection Velocity-3', 'value', 'face exterior')


        !
        ! Get normal vector
        !
        norm_1 = worker%normal(1)
        norm_2 = worker%normal(2)
        norm_3 = worker%normal(3)


        !
        ! Compute boundary average flux
        !
        flux_1 = HALF*(c1_m*u_m + c1_p*u_p) - HALF*(u_m+u_p)*u_grid 
        flux_2 = HALF*(c2_m*u_m + c2_p*u_p) - HALF*(u_m+u_p)*v_grid
        flux_3 = HALF*(c3_m*u_m + c3_p*u_p) - HALF*(u_m+u_p)*w_grid

        flux_1_ref = det_jacobian_grid*(jacobian_grid(:,1,1)*flux_1 + jacobian_grid(:,1,2)*flux_2 + jacobian_grid(:,1,3)*flux_3)
        flux_2_ref = det_jacobian_grid*(jacobian_grid(:,2,1)*flux_1 + jacobian_grid(:,2,2)*flux_2 + jacobian_grid(:,2,3)*flux_3)
        flux_3_ref = det_jacobian_grid*(jacobian_grid(:,3,1)*flux_1 + jacobian_grid(:,3,2)*flux_2 + jacobian_grid(:,3,3)*flux_3)




        !
        ! Dot with normal vector
        ! 
        integrand = flux_1_ref*norm_1 + flux_2_ref*norm_2 + flux_3_ref*norm_3


        !
        ! Integrate flux
        !
        call worker%integrate_boundary('u',integrand)


    end subroutine compute
    !**************************************************************************************************




end module SA_ale_boundary_average_advective_operator
