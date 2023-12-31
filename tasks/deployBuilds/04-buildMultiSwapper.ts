import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { IDeployerVMAdd } from 'tapioca-sdk/dist/ethers/hardhat/DeployerVM';
import { UniswapV2Swapper__factory } from 'tapioca-sdk/dist/typechain/tapioca-periphery';
import UniswapV2SwapperArtifact from 'tapioca-sdk/dist/artifacts/tapioca-periphery/UniswapV2Swapper.json';

export const buildMultiSwapper = async (
    hre: HardhatRuntimeEnvironment,
    uniV2Router: string,
    uniV2Factory: string,
): Promise<IDeployerVMAdd<UniswapV2Swapper__factory>> => {
    const UniswapV2Swapper = (await hre.ethers.getContractFactoryFromArtifact(
        UniswapV2SwapperArtifact,
    )) as UniswapV2Swapper__factory;

    return {
        contract: UniswapV2Swapper,
        deploymentName: 'MultiSwapper',
        args: [
            uniV2Router,
            uniV2Factory,
            // YieldBox, to be replaced by VM
            hre.ethers.constants.AddressZero,
        ],
        dependsOn: [{ argPosition: 2, deploymentName: 'YieldBox' }],
        runStaticSimulation: false,
    };
};
