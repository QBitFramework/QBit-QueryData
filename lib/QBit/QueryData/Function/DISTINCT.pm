package QBit::QueryData::Function::DISTINCT;

use qbit;

use base qw(QBit::QueryData::Function);

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    $self->{'FIELD'} = $self->args->[0];

    my $distinct_fields = $self->qd->{'__DISTINCT_FIELDS__'};

    #TODO: set_error
    throw gettex('You can use in request not more than one function "DISTINCT"') if @$distinct_fields > 1;

    push(@$distinct_fields, $self->field);
}

sub process {
    my ($self, $row) = @_;

    return $self->qd->_get_field_value_by_path($row, $row, undef, @{$self->qd->_get_path($self->{'FIELD'})});
}

TRUE;
