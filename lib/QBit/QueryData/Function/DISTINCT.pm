package QBit::QueryData::Function::DISTINCT;

use qbit;

use base qw(QBit::QueryData::Function);

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    $self->{'FIELD'} = $self->args->[0];

    unless (@{$self->qd->{'__GROUP_BY__'} // []}) {
        $self->qd->group_by(keys(%{$self->fields}));
    }
}

sub process {
    my ($self, $row) = @_;

    return $self->qd->_get_field_value_by_path($row, $row, undef, @{$self->qd->_get_path($self->{'FIELD'})});
}

sub post_process {$_[0]->qd->group_by()}

TRUE;
