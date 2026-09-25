# --
# Copyright (C) 2018 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::CustomerUser::CustomerCreate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::CustomerUser::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::CustomerUser::CustomerCreate

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerCreate');

    return $Self;
}

=item Run()

perform CustomerCreate Operation. This will return the created customer number.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',                            # UserLogin or SessionID is
                                                                                #   required
            SessionID => 123,
            Password  => 'some password',                                       # if UserLogin is sent then Password is required

            Customer => {
                CustomerID   => '12345',
                CustomerName => 'Test Inc.',
            },
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            CustomerID    => 123,                     # Customer  ID number in OTRS (help desk system)
            CustomerNumber => 2324454323322           # Customer Number in OTRS (Help desk system)
            ArticleID   => 43,                      # Article ID number in OTRS (help desk system)
            Error => {                              # should not return errors
                    ErrorCode    => 'Customer.Create.ErrorCode'
                    ErrorMessage => 'Error Description'
            },
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        $Self->ReturnError(
            ErrorCode    => 'Webservice.InvalidConfiguration',
            ErrorMessage => $Result->{ErrorMessage},
        );
    }

    # check needed stuff
    if (
        !$Param{Data}->{UserLogin}
        && !$Param{Data}->{SessionID}
        )
    {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCreate.MissingParameter',
            ErrorMessage => "CustomerCreate: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCreate.MissingParameter',
                ErrorMessage => "CustomerCreate: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCreate.AuthFail',
            ErrorMessage => "CustomerCreate: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;

    # check needed hashes
    for my $Needed (qw(Customer)) {
        if ( !IsHashRefWithData( $Param{Data}->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCreate.MissingParameter',
                ErrorMessage => "CustomerCreate: $Needed parameter is missing or not valid!",
            );
        }
    }

    # isolate customer parameter
    my $Customer = $Param{Data}->{Customer};

    # remove leading and trailing spaces
    for my $Attribute ( sort keys %{$Customer} ) {
        if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

            #remove leading spaces
            $Customer->{$Attribute} =~ s{\A\s+}{};

            #remove trailing spaces
            $Customer->{$Attribute} =~ s{\s+\z}{};
        }
    }

    my $CustomerCheck = $Self->_CheckCustomer( Customer => $Customer );

    if ( !$CustomerCheck->{Success} ) {
        return $Self->ReturnError( %{$CustomerCheck} );
    }

    return $Self->_CustomerCreate(
        Customer => $Customer,
        UserID   => $UserID,
    );
}

=begin Internal:

=item _CheckCustomer()

checks if the given customer parameters are valid.

    my $CustomerCheck = $OperationObject->_CheckCustomer(
        Customer => $Customer,                          # all customer parameters
    );

    returns:

    $CustomerCheck = {
        Success => 1,                               # if everything is OK
    }

    $CustomerCheck = {
        ErrorCode    => 'Function.Error',           # if error
        ErrorMessage => 'Error description',
    }

=cut

sub _CheckCustomer {
    my ( $Self, %Param ) = @_;

    my $Customer = $Param{Customer};

    # check customer internally
    for my $Needed (qw(CustomerID CustomerCompanyName)) {
        if ( !$Customer->{$Needed} ) {
            return {
                ErrorCode    => 'CustomerCreate.MissingParameter',
                ErrorMessage => "CustomerCreate: Customer->$Needed parameter is missing!",
            };
        }
    }

    # if everything is OK then return Success
    return {
        Success => 1,
    };
}

=item _CustomerCreate()

creates a customer with its article and sets dynamic fields and attachments if specified.

    my $Response = $OperationObject->_CustomerCreate(
        Customer => $Customer,       # all customer parameters
        UserID   => 123,
    );

    returns:

    $Response = {
        Success => 1,                # if everething is OK
        Data => {
            CustomerID => 123,
        }
    }

    $Response = {
        Success      => 0,           # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerCreate {
    my ( $Self, %Param ) = @_;

    my $Customer = $Param{Customer};

    # get customer object
    my $CustomerObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

    # create new customer
    my $CustomerID = $CustomerObject->CustomerCompanyAdd(
        CustomerID          => $Customer->{CustomerID},
        CustomerCompanyName => $Customer->{CustomerCompanyName},
        ValidID             => $Customer->{ValidID} // 1,
        UserID              => $Param{UserID},
    );

    if ( !$CustomerID ) {
        return {
            Success      => 0,
            ErrorMessage => 'Customer could not be created, please contact the system administrator',
        };
    }

    my %CustomerData = $CustomerObject->CustomerCompanyGet(
        CustomerID => $CustomerID,
        UserID     => $Param{UserID},
    );

    if ( !IsHashRefWithData( \%CustomerData ) ) {
        return {
            Success      => 0,
            ErrorMessage => 'Could not get new customer information, please contact the system'
                . ' administrator',
        };
    }

    return {
        Success => 1,
        Data    => {
            CustomerID => $CustomerID,
        },
    };
}

1;

=end Internal:

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
