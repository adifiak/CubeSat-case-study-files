package EOSmallSatCatalogue {
    doc /*
     * Pre-integrated (whitebox) catalogue for EOSmallSatProductLine.
     *
     * - Subsystem-level #integration blocks are already-configured realizations. The UVL
     *   derivation must treat them as leaf alternatives of the subsystem they specialize
     *   (e.g. FixedWings2x3U appears next to BodyPanels3U under eps/ModularEps/solarArray).
     * - System-level #integration blocks are known-valid reference products; they satisfy all
     *   assert constraints of the product line and can serve as round-trip oracles
     *   (configure in UVL -> generated whitebox should match).
     */
    private import OOSEM::OOSEM_Metadata::*;
    private import EOSmallSatProductLine::StructureThermal::*;
    private import EOSmallSatProductLine::Power::*;
    private import EOSmallSatProductLine::Gnc::*;
    private import EOSmallSatProductLine::DataHandling::*;
    private import EOSmallSatProductLine::Communications::*;
    private import EOSmallSatProductLine::Payloads::*;
    private import EOSmallSatProductLine::Propulsion::*;
    private import EOSmallSatProductLine::Mission::*;

    // ---- Electrical power ----

    #integration part def FixedWings2x3U :> DeployableWings {
        #design part :>> wingPanels : WingPanels2x3U;
        #design part :>> wingDeployment : BurnWireHinges;
    }

    #integration part def TrackingWings2x6U :> DeployableWings {
        #design part :>> wingPanels : WingPanels2x6U;
        #design part :>> wingDeployment : SolarArrayDriveAssembly;
    }

    #integration part def Eps6U_Standard :> ModularEps {
        #integration part :>> solarArray : FixedWings2x3U;
        #design part :>> battery : Battery2S4P;
        #design part :>> pcdu : PcduCompact;
    }

    #integration part def Eps12U_HighPower :> ModularEps {
        #integration part :>> solarArray : TrackingWings2x6U;
        #design part :>> battery : Battery4S4P;
        #design part :>> pcdu : PcduHighPower;
    }

    // ---- Guidance, navigation & control ----

    #integration part def StarTrackerSuite_Nano :> StarTrackerSuite {
        #design part :>> starTracker : NanoStarTracker;
        #design part :>> rateSensor[1] : MemsGyro;
    }

    #integration part def FineAdcs :> ModularAdcs {
        #integration part :>> attitudeSensors : StarTrackerSuite_Nano;
        #design part :>> actuators : ReactionWheels4Skewed;
    }

    // ---- Command & data handling ----

    #integration part def PayloadObc_LeonFpga :> ObcWithPayloadProcessor {
        #design part :>> flightProcessor : LeonFlightProcessor;
        #design part :>> payloadDataUnit[1] : FpgaMassMemory;
    }

    // ---- Communications ----

    #integration part def XBandTx_Qpsk :> XBandTransmitter {
        #design part :>> xbandModulator : QpskModulator;
        #design part :>> xbandAntenna : XBandPatchArray;
    }

    #integration part def XBandTx_DvbS2Horn :> XBandTransmitter {
        #design part :>> xbandModulator : DvbS2Modulator;
        #design part :>> xbandAntenna : XBandHornAntenna;
    }

    // ---- Imaging payloads ----

    #integration part def VhrTelescope_KorschTdi :> HighResTelescope {
        #design part :>> optics : Korsch150;
        #design part :>> focalPlane : MultispectralTdi;
    }

    // ---- Propulsion ----

    #integration part def FeepModule :> ElectricPropulsion {
        #design part :>> thruster : FeepThruster;
        #design part :>> propellantStore : IndiumReservoir;
    }

    // =================================================================================
    // Reference products (whiteboxes) - known-valid configurations of the product line
    // =================================================================================

    // 3U wide-area monitoring demonstrator
    #integration part def EOSat3U_Scout :> EOSatelliteDesign {
        #design part :>> structure : Structure3U;
        #design part :>> eps : CotsEpsKit3U;
        #design part :>> adcs : IntegratedAdcsUnit;
        #design part :>> obc : CotsArmObc;
        #design part :>> ttc : SBandTransceiver;
        #design part :>> payload : WideFieldMultispectralCam;
        #design part :>> thermal : PassiveThermal;
        #design part :>> payloadDownlink[0];
        #design part :>> propulsion[0];
        #design part :>> gnss[1] : SingleFrequencyGnss;
    }

    // 6U hyperspectral mapper with X-band downlink
    #integration part def EOSat6U_Hyperspectral :> EOSatelliteDesign {
        #design part :>> structure : Structure6U;
        #integration part :>> eps : Eps6U_Standard;
        #integration part :>> adcs : FineAdcs;
        #integration part :>> obc : PayloadObc_LeonFpga;
        #design part :>> ttc : UhfTransceiver;
        #design part :>> payload : HyperspectralImager;
        #design part :>> thermal : HeaterControlledThermal;
        #integration part :>> payloadDownlink[1] : XBandTx_Qpsk;
        #design part :>> propulsion[0];
        #design part :>> gnss[0];
    }

    // 12U very-high-resolution imager in a drag-compensated very low orbit
    #integration part def EOSat12U_VeryHighRes :> EOSatelliteDesign {
        #design part :>> structure : Structure12U;
        #integration part :>> eps : Eps12U_HighPower;
        #integration part :>> adcs : FineAdcs;
        #integration part :>> obc : PayloadObc_LeonFpga;
        #design part :>> ttc : SBandTransceiver;
        #integration part :>> payload : VhrTelescope_KorschTdi;
        #design part :>> thermal : DeployableRadiatorThermal;
        #integration part :>> payloadDownlink[1] : XBandTx_DvbS2Horn;
        #integration part :>> propulsion[1] : FeepModule;
        #design part :>> gnss[1] : DualFrequencyGnss;
    }
    
}
