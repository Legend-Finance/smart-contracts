"use strict";

const zeroAddress = '0x0000000000000000000000000000000000000000';

function toEther(n) {
    return web3.utils.toWei(n, "ether");
}

async function assertRevert (promise) {
    try {
        await promise;
    } catch (error) {
        console.log(error);
        const revertFound = error.message.search('revert') >= 0;
        assert(revertFound, `Expected "revert", got ${error} instead`);
    }
    return;
  }
async function computeY(r, S, A, n) {
    let y  = r;
    A.forEach((a, i) => {
        if(a != 0) {
          y = y*(S[i])%(n);
        }
    });

    return y;
}

module.exports = {
    assertRevert,
    computeY,
    toEther,
    zeroAddress,
};
