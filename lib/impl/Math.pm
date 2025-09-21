package Impl::Math::Add {


    sub add {
        my ($this, $a, $b) = @_;

        return $a + $b;
    }

}

package Impl::Math::Div {
    sub div {
        my ($this, $a, $b) = @_;

        return $a / $b;
    }
}

1;