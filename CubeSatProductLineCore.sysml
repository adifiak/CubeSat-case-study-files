package EOSmallSatProductLine {
    doc /*
     * Benchmark product line: CubeSat-class Earth-observation satellites (3U / 6U / 12U).
     *
     * Structured with the OOSEM v2 recursive decomposition pattern:
     *   #specification (blackbox)  - observable attributes and ports only
     *   #design        (greybox)   - decomposition into #specification subsystems,
     *                                attributes derived from the subsystems' blackbox attributes
     *   #integration   (whitebox)  - every subsystem redefined with a concrete realization
     *
     * Variation points are subsystems with multiplicity [1] (mandatory) or [0..1] (optional);
     * their alternatives are the #design / #integration blocks that specialize the subsystem's
     * #specification. Realization choices nest up to three levels below the root EOSatelliteDesign
     * (e.g. eps -> ModularEps.solarArray -> DeployableWings.wingPanels).
     *
     * Pre-integrated catalogue whiteboxes and reference products live in EOSmallSatCatalogue.sysml.
     *
     * Variation points are NOT independent. Dependencies are captured as assert constraints over
     * blackbox attributes, both inside nested greyboxes (e.g. battery string vs. PCDU, RF band of
     * front end vs. antenna, thruster vs. propellant) and at system level (mass, volume, power,
     * eclipse-energy and heat budgets; pointing, data-volume, storage, interface, thermal-stability,
     * orbit-maintenance and navigation dependencies).
     *
     * Units are encoded in attribute names (massKg, powerW, volumeU = 10x10x10 cm, ...).
     * powerW is always the orbit-average electrical load of a unit.
     */

    // =====================================================================================
    // Common definitions: enumerations, port definitions, and the common blackbox base
    // =====================================================================================
    package Common {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;

        enum def RfBand { enum uhf; enum sBand; enum xBand; }
        enum def PropellantType { enum xenon; enum iodine; enum indium; }

        port def LaunchRailInterface;      // CubeSat rails / deployer interface
        port def RegulatedPowerPort;       // regulated DC rails (3V3 / 5V / 12V)
        port def UnregulatedPowerPort;     // raw solar-array / battery bus
        port def CommandTelemetryPort;     // CAN-based command & telemetry bus
        port def PayloadDataPort;          // high-speed image data (LVDS / SpaceWire)
        port def RfCablePort;              // coax / IF link between RF units
        port def RfSpaceLinkPort;          // radiated link to / from the ground segment
        port def HeatPathPort;             // conductive heat path into the thermal control
        port def SunlightPort;             // incident solar flux
        port def OpticalAperturePort;      // light entering the imaging instrument
        port def OpticalBeamPort;          // converging beam from telescope optics to detector
        port def ThrustTransferPort;       // thrust transferred to the spacecraft body
        port def AttitudeTorquePort;       // control torque on the spacecraft body
        port def GnssSignalPort;           // navigation signals from GNSS constellations
        port def TimePulsePort;            // PPS timing pulse
        port def PropellantFeedPort;       // propellant feed line

        // Common blackbox of every unit that contributes to the spacecraft budgets.
        #specification part def SpacecraftUnit {
            attribute massKg : Real;       // mass incl. brackets and local harness
            attribute powerW : Real;       // orbit-average electrical load
            attribute volumeU : Real;      // internal volume occupied inside the structure
        }
    }

    // =====================================================================================
    // Structure and thermal control
    // =====================================================================================
    package StructureThermal {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import Common::*;

        #specification part def Structure :> SpacecraftUnit {
            attribute sizeU : Integer;             // CubeSat form factor
            attribute maxLaunchMassKg : Real;      // deployer mass limit (CDS)
            attribute usableVolumeU : Real;        // internal volume available for units
            port launchRails : LaunchRailInterface;
        }

        #design part def Structure3U :> Structure {
            attribute :>> massKg = 0.45;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> sizeU = 3;
            attribute :>> maxLaunchMassKg = 6.0;
            attribute :>> usableVolumeU = 2.7;
        }

        #design part def Structure6U :> Structure {
            attribute :>> massKg = 1.2;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> sizeU = 6;
            attribute :>> maxLaunchMassKg = 12.0;
            attribute :>> usableVolumeU = 5.4;
        }

        #design part def Structure12U :> Structure {
            attribute :>> massKg = 2.6;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> sizeU = 12;
            attribute :>> maxLaunchMassKg = 24.0;
            attribute :>> usableVolumeU = 10.8;
        }

        #specification part def ThermalControl :> SpacecraftUnit {
            attribute stabilityK : Real;           // achievable temperature stability at the payload
            attribute maxHeatRejectionW : Real;    // orbit-average dissipation it can reject
            port heatIn : ~HeatPathPort;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        // coatings + MLI only
        #design part def PassiveThermal :> ThermalControl {
            attribute :>> massKg = 0.1;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> stabilityK = 10.0;
            attribute :>> maxHeatRejectionW = 25.0;
        }

        // closed-loop heaters on the payload interface
        #design part def HeaterControlledThermal :> ThermalControl {
            attribute :>> massKg = 0.2;
            attribute :>> powerW = 1.5;
            attribute :>> volumeU = 0.05;
            attribute :>> stabilityK = 2.5;
            attribute :>> maxHeatRejectionW = 25.0;
        }

        // heaters + heat straps + deployable radiator panel
        #design part def DeployableRadiatorThermal :> ThermalControl {
            attribute :>> massKg = 0.9;
            attribute :>> powerW = 2.0;
            attribute :>> volumeU = 0.1;
            attribute :>> stabilityK = 1.5;
            attribute :>> maxHeatRejectionW = 70.0;
        }
    }

    // =====================================================================================
    // Electrical power subsystem (recursive: EPS -> solar array -> wing panels / deployment)
    // =====================================================================================
    package Power {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import Common::*;

        #specification part def ElectricalPowerSystem :> SpacecraftUnit {
            attribute orbitAvgPowerW : Real;       // orbit-average power delivered to the loads
            attribute usableEnergyWh : Real;       // battery energy usable per eclipse
            attribute minStructureU : Integer;     // structure sizes the solar array can be fitted to
            attribute maxStructureU : Integer;
            port sunlight : SunlightPort;
            port powerOut : RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        // COTS kit: body-mounted 3U panels, 2S2P battery and PCDU sold as one qualified unit
        #design part def CotsEpsKit3U :> ElectricalPowerSystem {
            attribute :>> massKg = 0.55;
            attribute :>> powerW = 0.15;
            attribute :>> volumeU = 0.3;
            attribute :>> orbitAvgPowerW = 7.0;
            attribute :>> usableEnergyWh = 11.4;
            attribute :>> minStructureU = 3;
            attribute :>> maxStructureU = 3;
        }

        #design part def ModularEps :> ElectricalPowerSystem {
            #specification part solarArray[1] : SolarArray;
            #specification part battery[1] : BatteryPack;
            #specification part pcdu[1] : PowerConditioningUnit;

            attribute :>> massKg = solarArray.massKg + battery.massKg + pcdu.massKg;
            attribute :>> powerW = solarArray.powerW + pcdu.powerW;
            attribute :>> volumeU = solarArray.volumeU + battery.volumeU + pcdu.volumeU;
            attribute :>> orbitAvgPowerW = solarArray.orbitAvgPowerW * pcdu.efficiency;
            attribute :>> usableEnergyWh = battery.capacityWh * battery.maxDepthOfDischarge;
            attribute :>> minStructureU = solarArray.minStructureU;
            attribute :>> maxStructureU = solarArray.maxStructureU;

            bind sunlight = solarArray.sunlight;
            bind powerOut = pcdu.powerOut;
            bind cdhBus = pcdu.cdhBus;
            interface solarArray.powerOut to pcdu.solarIn;
            interface battery.busPort to pcdu.batteryPort;

            // the PCDU's MPPT inputs must be rated for the array's peak power
            assert constraint solarInputRating { solarArray.peakPowerW <= pcdu.maxSolarInputW }
            // the battery string must match the PCDU's charge regulator
            assert constraint batteryStringMatch { battery.seriesCells == pcdu.batterySeriesCells }
        }

        #specification part def SolarArray :> SpacecraftUnit {
            attribute peakPowerW : Real;
            attribute orbitAvgPowerW : Real;
            attribute minStructureU : Integer;
            attribute maxStructureU : Integer;
            port sunlight : SunlightPort;
            port powerOut : UnregulatedPowerPort;
        }

        #design part def BodyPanels3U :> SolarArray {
            attribute :>> massKg = 0.25;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> peakPowerW = 12.0;
            attribute :>> orbitAvgPowerW = 6.6;
            attribute :>> minStructureU = 3;
            attribute :>> maxStructureU = 3;
        }

        #design part def BodyPanels6U :> SolarArray {
            attribute :>> massKg = 0.45;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> peakPowerW = 20.0;
            attribute :>> orbitAvgPowerW = 11.2;
            attribute :>> minStructureU = 6;
            attribute :>> maxStructureU = 6;
        }

        #design part def BodyPanels12U :> SolarArray {
            attribute :>> massKg = 0.8;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> peakPowerW = 34.0;
            attribute :>> orbitAvgPowerW = 18.7;
            attribute :>> minStructureU = 12;
            attribute :>> maxStructureU = 12;
        }

        #design part def DeployableWings :> SolarArray {
            #specification part wingPanels[1] : WingPanelSet;
            #specification part wingDeployment[1] : DeploymentMechanism;

            attribute :>> massKg = wingPanels.massKg + wingDeployment.massKg;
            attribute :>> powerW = wingPanels.powerW + wingDeployment.powerW;
            attribute :>> volumeU = wingPanels.volumeU + wingDeployment.volumeU;
            attribute :>> peakPowerW = wingPanels.peakPowerW;
            attribute :>> orbitAvgPowerW = wingPanels.peakPowerW * wingDeployment.orbitAvgFactor;
            attribute :>> minStructureU = wingPanels.minStructureU;
            attribute :>> maxStructureU = 12;

            bind sunlight = wingPanels.sunlight;
            bind powerOut = wingPanels.powerOut;
        }

        #specification part def WingPanelSet :> SpacecraftUnit {
            attribute peakPowerW : Real;
            attribute minStructureU : Integer;     // shortest structure edge the wings can hinge on
            port sunlight : SunlightPort;
            port powerOut : UnregulatedPowerPort;
        }

        #design part def WingPanels2x3U :> WingPanelSet {
            attribute :>> massKg = 0.75;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> peakPowerW = 42.0;
            attribute :>> minStructureU = 3;
        }

        #design part def WingPanels2x6U :> WingPanelSet {
            attribute :>> massKg = 1.5;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> peakPowerW = 84.0;
            attribute :>> minStructureU = 6;
        }

        #specification part def DeploymentMechanism :> SpacecraftUnit {
            attribute orbitAvgFactor : Real;       // orbit-average / peak power ratio it enables
        }

        // fixed wings released by burn wire
        #design part def BurnWireHinges :> DeploymentMechanism {
            attribute :>> massKg = 0.08;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.05;
            attribute :>> orbitAvgFactor = 0.55;
        }

        // sun-tracking solar array drive assembly
        #design part def SolarArrayDriveAssembly :> DeploymentMechanism {
            attribute :>> massKg = 0.35;
            attribute :>> powerW = 0.8;
            attribute :>> volumeU = 0.3;
            attribute :>> orbitAvgFactor = 0.75;
        }

        #specification part def BatteryPack :> SpacecraftUnit {
            attribute capacityWh : Real;
            attribute seriesCells : Integer;
            attribute maxDepthOfDischarge : Real;  // allowed DoD for LEO cycle life
            port busPort : UnregulatedPowerPort;
        }

        #design part def Battery2S2P :> BatteryPack {
            attribute :>> massKg = 0.27;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.2;
            attribute :>> capacityWh = 38.0;
            attribute :>> seriesCells = 2;
            attribute :>> maxDepthOfDischarge = 0.3;
        }

        #design part def Battery2S4P :> BatteryPack {
            attribute :>> massKg = 0.5;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.35;
            attribute :>> capacityWh = 77.0;
            attribute :>> seriesCells = 2;
            attribute :>> maxDepthOfDischarge = 0.3;
        }

        #design part def Battery4S4P :> BatteryPack {
            attribute :>> massKg = 0.95;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.7;
            attribute :>> capacityWh = 154.0;
            attribute :>> seriesCells = 4;
            attribute :>> maxDepthOfDischarge = 0.3;
        }

        #specification part def PowerConditioningUnit :> SpacecraftUnit {
            attribute maxSolarInputW : Real;
            attribute efficiency : Real;
            attribute batterySeriesCells : Integer;
            port solarIn : ~UnregulatedPowerPort;
            port batteryPort : ~UnregulatedPowerPort;
            port powerOut : RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        #design part def PcduCompact :> PowerConditioningUnit {
            attribute :>> massKg = 0.12;
            attribute :>> powerW = 0.2;
            attribute :>> volumeU = 0.15;
            attribute :>> maxSolarInputW = 45.0;
            attribute :>> efficiency = 0.9;
            attribute :>> batterySeriesCells = 2;
        }

        #design part def PcduHighPower :> PowerConditioningUnit {
            attribute :>> massKg = 0.3;
            attribute :>> powerW = 0.5;
            attribute :>> volumeU = 0.3;
            attribute :>> maxSolarInputW = 160.0;
            attribute :>> efficiency = 0.92;
            attribute :>> batterySeriesCells = 4;
        }

    }

    // =====================================================================================
    // Guidance, navigation & control (recursive: ADCS -> sensor suite -> star tracker / gyro)
    // =====================================================================================
    package Gnc {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import SequenceFunctions::notEmpty;
        private import RealFunctions::sum;
        private import Common::*;

        #specification part def AttitudeDeterminationControl :> SpacecraftUnit {
            attribute pointingAccuracyDeg : Real;      // absolute pointing error (3 sigma)
            attribute threeAxis : Boolean;             // three-axis stabilised
            attribute momentumCapacityMNms : Real;     // stored angular momentum capacity
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
            port controlTorque : AttitudeTorquePort;
        }

        // magnetometer + magnetorquers only: detumbling and coarse nadir alignment
        #design part def MagneticAdcs :> AttitudeDeterminationControl {
            attribute :>> massKg = 0.12;
            attribute :>> powerW = 0.4;
            attribute :>> volumeU = 0.15;
            attribute :>> pointingAccuracyDeg = 10.0;
            attribute :>> threeAxis = false;
            attribute :>> momentumCapacityMNms = 0.0;
        }

        // COTS all-in-one unit (sun sensors, magnetometer, three small wheels, magnetorquers)
        #design part def IntegratedAdcsUnit :> AttitudeDeterminationControl {
            attribute :>> massKg = 0.6;
            attribute :>> powerW = 1.8;
            attribute :>> volumeU = 0.5;
            attribute :>> pointingAccuracyDeg = 1.0;
            attribute :>> threeAxis = true;
            attribute :>> momentumCapacityMNms = 17.0;
        }

        #design part def ModularAdcs :> AttitudeDeterminationControl {
            #specification part attitudeSensors[1] : AttitudeSensorSuite;
            #specification part actuators[1] : ActuatorAssembly;
            part adcsController : AdcsControllerBoard;     // fixed, non-variable part

            attribute :>> massKg = attitudeSensors.massKg + actuators.massKg + adcsController.massKg;
            attribute :>> powerW = attitudeSensors.powerW + actuators.powerW + adcsController.powerW;
            attribute :>> volumeU = attitudeSensors.volumeU + actuators.volumeU + adcsController.volumeU;
            attribute :>> pointingAccuracyDeg = attitudeSensors.knowledgeDeg + actuators.controlErrorDeg;
            attribute :>> threeAxis = true;
            attribute :>> momentumCapacityMNms = actuators.momentumMNms;

            bind cdhBus = adcsController.cdhBus;
            bind controlTorque = actuators.torqueOut;
            interface attitudeSensors.measurements to adcsController.sensorsIn;
            interface adcsController.actuatorCmd to actuators.commandIn;
        }

        part def AdcsControllerBoard {
            attribute massKg : Real = 0.06;
            attribute powerW : Real = 0.3;
            attribute volumeU : Real = 0.1;
            port cdhBus : CommandTelemetryPort;
            port sensorsIn : ~CommandTelemetryPort;
            port actuatorCmd : ~CommandTelemetryPort;
        }

        #specification part def AttitudeSensorSuite :> SpacecraftUnit {
            attribute knowledgeDeg : Real;             // attitude knowledge error (3 sigma)
            port measurements : CommandTelemetryPort;
        }

        #design part def SunMagSensorSuite :> AttitudeSensorSuite {
            attribute :>> massKg = 0.08;
            attribute :>> powerW = 0.25;
            attribute :>> volumeU = 0.1;
            attribute :>> knowledgeDeg = 0.8;
        }

        #design part def StarTrackerSuite :> AttitudeSensorSuite {
            #specification part starTracker[1] : StarTracker;
            #specification part rateSensor[0..1] : RateSensor;
            part coarseSunSensors : CoarseSunSensorSet;    // fixed: acquisition and safe mode

            attribute :>> massKg = sum((starTracker.massKg, rateSensor.massKg, coarseSunSensors.massKg));
            attribute :>> powerW = sum((starTracker.powerW, rateSensor.powerW, coarseSunSensors.powerW));
            attribute :>> volumeU = sum((starTracker.volumeU, rateSensor.volumeU, coarseSunSensors.volumeU));
            // gyro blending reduces the knowledge error
            attribute :>> knowledgeDeg = if notEmpty(rateSensor) ? starTracker.knowledgeDeg * rateSensor.blendingFactor
                                                                 else starTracker.knowledgeDeg;

            bind measurements = starTracker.attitudeOut;
        }

        part def CoarseSunSensorSet {
            attribute massKg : Real = 0.03;
            attribute powerW : Real = 0.05;
            attribute volumeU : Real = 0.0;
        }

        #specification part def StarTracker :> SpacecraftUnit {
            attribute knowledgeDeg : Real;
            port attitudeOut : CommandTelemetryPort;
        }

        #design part def NanoStarTracker :> StarTracker {
            attribute :>> massKg = 0.1;
            attribute :>> powerW = 0.7;
            attribute :>> volumeU = 0.25;
            attribute :>> knowledgeDeg = 0.02;
        }

        #design part def DualHeadStarTracker :> StarTracker {
            attribute :>> massKg = 0.45;
            attribute :>> powerW = 1.5;
            attribute :>> volumeU = 0.5;
            attribute :>> knowledgeDeg = 0.005;
        }

        #specification part def RateSensor :> SpacecraftUnit {
            attribute blendingFactor : Real;           // knowledge-error reduction when blended
        }

        #design part def MemsGyro :> RateSensor {
            attribute :>> massKg = 0.05;
            attribute :>> powerW = 0.2;
            attribute :>> volumeU = 0.05;
            attribute :>> blendingFactor = 0.8;
        }

        #design part def FiberOpticGyro :> RateSensor {
            attribute :>> massKg = 0.6;
            attribute :>> powerW = 2.0;
            attribute :>> volumeU = 0.4;
            attribute :>> blendingFactor = 0.5;
        }

        #specification part def ActuatorAssembly :> SpacecraftUnit {
            attribute controlErrorDeg : Real;
            attribute momentumMNms : Real;
            port commandIn : CommandTelemetryPort;
            port torqueOut : AttitudeTorquePort;
        }

        #design part def ReactionWheels3 :> ActuatorAssembly {
            attribute :>> massKg = 0.65;
            attribute :>> powerW = 1.2;
            attribute :>> volumeU = 0.4;
            attribute :>> controlErrorDeg = 0.05;
            attribute :>> momentumMNms = 10.0;
        }

        // four wheels in a skewed pyramid (one-fault tolerant) + magnetorquers
        #design part def ReactionWheels4Skewed :> ActuatorAssembly {
            attribute :>> massKg = 1.2;
            attribute :>> powerW = 2.2;
            attribute :>> volumeU = 0.7;
            attribute :>> controlErrorDeg = 0.03;
            attribute :>> momentumMNms = 32.0;
        }

        #specification part def GnssReceiver :> SpacecraftUnit {
            attribute positionAccuracyM : Real;
            port signalIn : GnssSignalPort;
            port pps : TimePulsePort;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        #design part def SingleFrequencyGnss :> GnssReceiver {
            attribute :>> massKg = 0.03;
            attribute :>> powerW = 0.25;
            attribute :>> volumeU = 0.05;
            attribute :>> positionAccuracyM = 10.0;
        }

        #design part def DualFrequencyGnss :> GnssReceiver {
            attribute :>> massKg = 0.1;
            attribute :>> powerW = 0.9;
            attribute :>> volumeU = 0.1;
            attribute :>> positionAccuracyM = 1.5;
        }

    }

    // =====================================================================================
    // Command & data handling
    // =====================================================================================
    package DataHandling {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import SequenceFunctions::notEmpty;
        private import SequenceFunctions::isEmpty;
        private import RealFunctions::sum;
        private import Common::*;

        #specification part def OnboardComputer :> SpacecraftUnit {
            attribute storageGbit : Real;
            attribute supportsSpaceWire : Boolean;
            attribute dataReductionFactor : Real;      // downlinked / acquired volume (1.0 = none)
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : ~CommandTelemetryPort;       // bus master
            port payloadDataIn : ~PayloadDataPort;
            port downlinkDataOut : PayloadDataPort;
            port ppsIn : ~TimePulsePort;
        }

        #design part def CotsArmObc :> OnboardComputer {
            attribute :>> massKg = 0.1;
            attribute :>> powerW = 0.4;
            attribute :>> volumeU = 0.2;
            attribute :>> storageGbit = 64.0;
            attribute :>> supportsSpaceWire = false;
            attribute :>> dataReductionFactor = 1.0;
        }

        #design part def RadTolerantObc :> OnboardComputer {
            attribute :>> massKg = 0.25;
            attribute :>> powerW = 1.6;
            attribute :>> volumeU = 0.3;
            attribute :>> storageGbit = 16.0;
            attribute :>> supportsSpaceWire = true;
            attribute :>> dataReductionFactor = 1.0;
        }

        #design part def ObcWithPayloadProcessor :> OnboardComputer {
            #specification part flightProcessor[1] : FlightProcessor;
            #specification part payloadDataUnit[0..1] : PayloadDataUnit;

            attribute :>> massKg = sum((flightProcessor.massKg, payloadDataUnit.massKg));
            attribute :>> powerW = sum((flightProcessor.powerW, payloadDataUnit.powerW));
            attribute :>> volumeU = sum((flightProcessor.volumeU, payloadDataUnit.volumeU));
            attribute :>> storageGbit = sum((flightProcessor.storageGbit, payloadDataUnit.storageGbit));
            attribute :>> supportsSpaceWire = flightProcessor.supportsSpaceWire or
                (notEmpty(payloadDataUnit) and payloadDataUnit.supportsSpaceWire);
            attribute :>> dataReductionFactor = if notEmpty(payloadDataUnit) ? payloadDataUnit.dataReductionFactor
                                                                           else 1.0;

            bind cdhBus = flightProcessor.cdhBus;
            bind ppsIn = flightProcessor.ppsIn;
            interface flightProcessor.processorLink to payloadDataUnit.hostLink;

            // the GPU edge module ships Linux drivers only
            assert constraint hostCompatibility {
                isEmpty(payloadDataUnit) or (payloadDataUnit.requiresLinuxHost implies flightProcessor.runsLinux)
            }
        }

        #specification part def FlightProcessor :> SpacecraftUnit {
            attribute storageGbit : Real;
            attribute supportsSpaceWire : Boolean;
            attribute runsLinux : Boolean;
            port cdhBus : ~CommandTelemetryPort;
            port ppsIn : ~TimePulsePort;
            port processorLink : PayloadDataPort;
        }

        #design part def ArmFlightProcessor :> FlightProcessor {
            attribute :>> massKg = 0.08;
            attribute :>> powerW = 0.35;
            attribute :>> volumeU = 0.15;
            attribute :>> storageGbit = 32.0;
            attribute :>> supportsSpaceWire = false;
            attribute :>> runsLinux = true;
        }

        #design part def LeonFlightProcessor :> FlightProcessor {
            attribute :>> massKg = 0.2;
            attribute :>> powerW = 1.4;
            attribute :>> volumeU = 0.25;
            attribute :>> storageGbit = 8.0;
            attribute :>> supportsSpaceWire = true;
            attribute :>> runsLinux = false;
        }

        #specification part def PayloadDataUnit :> SpacecraftUnit {
            attribute storageGbit : Real;
            attribute supportsSpaceWire : Boolean;
            attribute dataReductionFactor : Real;
            attribute requiresLinuxHost : Boolean;
            port hostLink : ~PayloadDataPort;
        }

        // mass memory with lossless (CCSDS 123) compression
        #design part def FpgaMassMemory :> PayloadDataUnit {
            attribute :>> massKg = 0.18;
            attribute :>> powerW = 2.5;
            attribute :>> volumeU = 0.25;
            attribute :>> storageGbit = 512.0;
            attribute :>> supportsSpaceWire = true;
            attribute :>> dataReductionFactor = 0.5;
            attribute :>> requiresLinuxHost = false;
        }

        // on-board cloud screening / AI tasking: only useful scenes are downlinked
        #design part def GpuEdgeProcessor :> PayloadDataUnit {
            attribute :>> massKg = 0.25;
            attribute :>> powerW = 7.0;
            attribute :>> volumeU = 0.35;
            attribute :>> storageGbit = 256.0;
            attribute :>> supportsSpaceWire = false;
            attribute :>> dataReductionFactor = 0.2;
            attribute :>> requiresLinuxHost = true;
        }

    }

    // =====================================================================================
    // Communications: TT&C radio and optional high-rate payload downlink
    // =====================================================================================
    package Communications {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import Common::*;

        #specification part def TtcRadio :> SpacecraftUnit {
            attribute dataRateMbps : Real;
            port spaceLink : RfSpaceLinkPort;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        #design part def UhfTransceiver :> TtcRadio {
            attribute :>> massKg = 0.09;
            attribute :>> powerW = 0.8;
            attribute :>> volumeU = 0.15;
            attribute :>> dataRateMbps = 0.0096;
        }

        #design part def SBandTransceiver :> TtcRadio {
            attribute :>> massKg = 0.2;
            attribute :>> powerW = 2.0;
            attribute :>> volumeU = 0.25;
            attribute :>> dataRateMbps = 2.0;
        }

        #design part def SdrTransceiver :> TtcRadio {
            #specification part rfFrontEnd[1] : RfFrontEnd;
            #specification part ttcAntenna[1] : TtcAntenna;
            part baseband : SdrBasebandBoard;              // fixed, non-variable part

            attribute :>> massKg = rfFrontEnd.massKg + ttcAntenna.massKg + baseband.massKg;
            attribute :>> powerW = rfFrontEnd.powerW + ttcAntenna.powerW + baseband.powerW;
            attribute :>> volumeU = rfFrontEnd.volumeU + ttcAntenna.volumeU + baseband.volumeU;
            attribute :>> dataRateMbps = rfFrontEnd.maxDataRateMbps;

            bind spaceLink = ttcAntenna.spaceLink;
            bind cdhBus = baseband.cdhBus;
            interface baseband.ifLink to rfFrontEnd.ifLink;
            interface rfFrontEnd.antennaPort to ttcAntenna.feedPort;

            assert constraint bandMatch { rfFrontEnd.band == ttcAntenna.band }
        }

        part def SdrBasebandBoard {
            attribute massKg : Real = 0.06;
            attribute powerW : Real = 1.1;
            attribute volumeU : Real = 0.15;
            port cdhBus : CommandTelemetryPort;
            port ifLink : RfCablePort;
        }

        #specification part def RfFrontEnd :> SpacecraftUnit {
            attribute band : RfBand;
            attribute maxDataRateMbps : Real;
            port ifLink : ~RfCablePort;
            port antennaPort : RfCablePort;
        }

        #design part def UhfFrontEnd :> RfFrontEnd {
            attribute :>> massKg = 0.05;
            attribute :>> powerW = 0.3;
            attribute :>> volumeU = 0.05;
            attribute :>> band = RfBand::uhf;
            attribute :>> maxDataRateMbps = 0.1;
        }

        #design part def SBandFrontEnd :> RfFrontEnd {
            attribute :>> massKg = 0.08;
            attribute :>> powerW = 0.9;
            attribute :>> volumeU = 0.1;
            attribute :>> band = RfBand::sBand;
            attribute :>> maxDataRateMbps = 4.0;
        }

        #specification part def TtcAntenna :> SpacecraftUnit {
            attribute band : RfBand;
            port feedPort : ~RfCablePort;
            port spaceLink : RfSpaceLinkPort;
        }

        #design part def UhfTurnstileAntenna :> TtcAntenna {
            attribute :>> massKg = 0.08;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.05;
            attribute :>> band = RfBand::uhf;
        }

        #design part def SBandPatchAntenna :> TtcAntenna {
            attribute :>> massKg = 0.05;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> band = RfBand::sBand;
        }

        #specification part def PayloadDownlinkTransmitter :> SpacecraftUnit {
            attribute dataRateMbps : Real;
            attribute requiredPointingDeg : Real;      // antenna pointing needed to close the link
            port dataIn : ~PayloadDataPort;
            port spaceLink : RfSpaceLinkPort;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        #design part def SBandHighRateTx :> PayloadDownlinkTransmitter {
            attribute :>> massKg = 0.25;
            attribute :>> powerW = 1.2;
            attribute :>> volumeU = 0.3;
            attribute :>> dataRateMbps = 10.0;
            attribute :>> requiredPointingDeg = 15.0;
        }

        #design part def XBandTransmitter :> PayloadDownlinkTransmitter {
            #specification part xbandModulator[1] : XBandModulator;
            #specification part xbandAntenna[1] : XBandAntenna;

            attribute :>> massKg = xbandModulator.massKg + xbandAntenna.massKg;
            attribute :>> powerW = xbandModulator.powerW + xbandAntenna.powerW;
            attribute :>> volumeU = xbandModulator.volumeU + xbandAntenna.volumeU;
            attribute :>> dataRateMbps = xbandModulator.dataRateMbps;
            attribute :>> requiredPointingDeg = xbandAntenna.requiredPointingDeg;

            bind dataIn = xbandModulator.dataIn;
            bind spaceLink = xbandAntenna.spaceLink;
            interface xbandModulator.rfOut to xbandAntenna.feedPort;

            // antenna gain must close the link budget at the modulator's symbol rate
            assert constraint linkBudget { xbandModulator.dataRateMbps <= xbandAntenna.maxDataRateMbps }
        }

        #specification part def XBandModulator :> SpacecraftUnit {
            attribute dataRateMbps : Real;
            port dataIn : ~PayloadDataPort;
            port rfOut : RfCablePort;
        }

        #design part def QpskModulator :> XBandModulator {
            attribute :>> massKg = 0.2;
            attribute :>> powerW = 1.4;
            attribute :>> volumeU = 0.3;
            attribute :>> dataRateMbps = 50.0;
        }

        #design part def DvbS2Modulator :> XBandModulator {
            attribute :>> massKg = 0.4;
            attribute :>> powerW = 2.2;
            attribute :>> volumeU = 0.35;
            attribute :>> dataRateMbps = 150.0;
        }

        #specification part def XBandAntenna :> SpacecraftUnit {
            attribute maxDataRateMbps : Real;
            attribute requiredPointingDeg : Real;
            port feedPort : ~RfCablePort;
            port spaceLink : RfSpaceLinkPort;
        }

        #design part def XBandPatchArray :> XBandAntenna {
            attribute :>> massKg = 0.1;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.0;
            attribute :>> maxDataRateMbps = 60.0;
            attribute :>> requiredPointingDeg = 3.0;
        }

        #design part def XBandHornAntenna :> XBandAntenna {
            attribute :>> massKg = 0.35;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.2;
            attribute :>> maxDataRateMbps = 200.0;
            attribute :>> requiredPointingDeg = 1.2;
        }

    }

    // =====================================================================================
    // Imaging payloads (recursive: payload -> high-resolution telescope -> optics / focal plane)
    // =====================================================================================
    package Payloads {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import Common::*;

        #specification part def ImagingPayload :> SpacecraftUnit {
            attribute groundSampleDistanceM : Real;
            attribute dailyDataGbit : Real;            // raw data acquired per day
            attribute requiredPointingDeg : Real;
            attribute requiredThermalStabilityK : Real;
            attribute designAltitudeKm : Real;         // operating altitude the instrument is designed for
            attribute needsSpaceWire : Boolean;
            attribute needsPreciseOrbit : Boolean;     // orbit knowledge needed for georeferencing
            port aperture : OpticalAperturePort;
            port imageDataOut : PayloadDataPort;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
            port heatOut : HeatPathPort;
        }

        #design part def WideFieldMultispectralCam :> ImagingPayload {
            attribute :>> massKg = 0.35;
            attribute :>> powerW = 1.5;
            attribute :>> volumeU = 0.5;
            attribute :>> groundSampleDistanceM = 22.0;
            attribute :>> dailyDataGbit = 2.0;
            attribute :>> requiredPointingDeg = 12.0;
            attribute :>> requiredThermalStabilityK = 12.0;
            attribute :>> designAltitudeKm = 550.0;
            attribute :>> needsSpaceWire = false;
            attribute :>> needsPreciseOrbit = false;
        }

        #design part def HyperspectralImager :> ImagingPayload {
            attribute :>> massKg = 2.2;
            attribute :>> powerW = 6.0;
            attribute :>> volumeU = 1.5;
            attribute :>> groundSampleDistanceM = 30.0;
            attribute :>> dailyDataGbit = 180.0;
            attribute :>> requiredPointingDeg = 0.5;
            attribute :>> requiredThermalStabilityK = 3.0;
            attribute :>> designAltitudeKm = 550.0;
            attribute :>> needsSpaceWire = true;
            attribute :>> needsPreciseOrbit = false;
        }

        #design part def HighResTelescope :> ImagingPayload {
            #specification part optics[1] : TelescopeOptics;
            #specification part focalPlane[1] : FocalPlaneAssembly;
            part focusMechanism : FocusMechanism;          // fixed, non-variable part

            attribute :>> massKg = optics.massKg + focalPlane.massKg + focusMechanism.massKg;
            attribute :>> powerW = optics.powerW + focalPlane.powerW + focusMechanism.powerW;
            attribute :>> volumeU = optics.volumeU + focalPlane.volumeU + focusMechanism.volumeU;
            // GSD [m] = altitude [km] * pixel pitch [um] / focal length [mm]
            attribute :>> groundSampleDistanceM = optics.designAltitudeKm * focalPlane.pixelPitchUm / optics.focalLengthMm;
            attribute :>> dailyDataGbit = focalPlane.dailyDataGbit;
            attribute :>> requiredPointingDeg = optics.requiredPointingDeg;
            attribute :>> requiredThermalStabilityK =
                if optics.requiredThermalStabilityK < focalPlane.requiredThermalStabilityK ? optics.requiredThermalStabilityK
                else focalPlane.requiredThermalStabilityK;
            attribute :>> designAltitudeKm = optics.designAltitudeKm;
            attribute :>> needsSpaceWire = focalPlane.needsSpaceWire;
            attribute :>> needsPreciseOrbit = true;

            bind aperture = optics.aperture;
            bind imageDataOut = focalPlane.imageDataOut;
            bind heatOut = focalPlane.heatOut;
            interface optics.imageBeam to focalPlane.beamIn;

            // the detector must lie within the telescope's corrected image circle
            assert constraint sensorFitsImageCircle { focalPlane.sensorDiagonalMm <= optics.imageCircleMm }
        }

        part def FocusMechanism {
            attribute massKg : Real = 0.1;
            attribute powerW : Real = 0.2;
            attribute volumeU : Real = 0.1;
        }

        #specification part def TelescopeOptics :> SpacecraftUnit {
            attribute focalLengthMm : Real;
            attribute imageCircleMm : Real;
            attribute requiredPointingDeg : Real;
            attribute requiredThermalStabilityK : Real;
            attribute designAltitudeKm : Real;
            port aperture : OpticalAperturePort;
            port imageBeam : OpticalBeamPort;
        }

        #design part def Cassegrain95 :> TelescopeOptics {
            attribute :>> massKg = 1.6;
            attribute :>> powerW = 0.3;
            attribute :>> volumeU = 1.5;
            attribute :>> focalLengthMm = 580.0;
            attribute :>> imageCircleMm = 20.0;
            attribute :>> requiredPointingDeg = 0.1;
            attribute :>> requiredThermalStabilityK = 5.0;
            attribute :>> designAltitudeKm = 550.0;
        }

        // large-aperture Korsch telescope designed for a very-low (drag-dominated) orbit
        #design part def Korsch150 :> TelescopeOptics {
            attribute :>> massKg = 4.2;
            attribute :>> powerW = 0.8;
            attribute :>> volumeU = 4.0;
            attribute :>> focalLengthMm = 1200.0;
            attribute :>> imageCircleMm = 40.0;
            attribute :>> requiredPointingDeg = 0.065;
            attribute :>> requiredThermalStabilityK = 2.0;
            attribute :>> designAltitudeKm = 420.0;
        }

        #specification part def FocalPlaneAssembly :> SpacecraftUnit {
            attribute pixelPitchUm : Real;
            attribute sensorDiagonalMm : Real;
            attribute dailyDataGbit : Real;
            attribute requiredThermalStabilityK : Real;
            attribute needsSpaceWire : Boolean;
            port beamIn : ~OpticalBeamPort;
            port imageDataOut : PayloadDataPort;
            port heatOut : HeatPathPort;
        }

        #design part def PanchromaticCmos :> FocalPlaneAssembly {
            attribute :>> massKg = 0.2;
            attribute :>> powerW = 2.5;
            attribute :>> volumeU = 0.3;
            attribute :>> pixelPitchUm = 5.5;
            attribute :>> sensorDiagonalMm = 16.0;
            attribute :>> dailyDataGbit = 40.0;
            attribute :>> requiredThermalStabilityK = 5.0;
            attribute :>> needsSpaceWire = false;
        }

        #design part def MultispectralTdi :> FocalPlaneAssembly {
            attribute :>> massKg = 0.4;
            attribute :>> powerW = 5.0;
            attribute :>> volumeU = 0.5;
            attribute :>> pixelPitchUm = 7.0;
            attribute :>> sensorDiagonalMm = 28.0;
            attribute :>> dailyDataGbit = 120.0;
            attribute :>> requiredThermalStabilityK = 2.0;
            attribute :>> needsSpaceWire = true;
        }

    }

    // =====================================================================================
    // Propulsion (optional)
    // =====================================================================================
    package Propulsion {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import Common::*;

        #specification part def PropulsionSystem :> SpacecraftUnit {
            attribute totalImpulseNs : Real;
            attribute requiresThreeAxis : Boolean;     // thrust vector must be pointed
            port thrust : ThrustTransferPort;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
        }

        #design part def ColdGasThruster :> PropulsionSystem {
            attribute :>> massKg = 0.9;
            attribute :>> powerW = 0.2;
            attribute :>> volumeU = 0.5;
            attribute :>> totalImpulseNs = 60.0;
            attribute :>> requiresThreeAxis = true;
        }

        #design part def ElectricPropulsion :> PropulsionSystem {
            #specification part thruster[1] : ElectricThruster;
            #specification part propellantStore[1] : PropellantStorage;
            part ppu : PowerProcessingUnit;                // fixed, non-variable part

            attribute :>> massKg = thruster.massKg + propellantStore.massKg + ppu.massKg;
            attribute :>> powerW = thruster.powerW + propellantStore.powerW + ppu.powerW;
            attribute :>> volumeU = thruster.volumeU + propellantStore.volumeU + ppu.volumeU;
            attribute :>> totalImpulseNs = thruster.specificImpulseS * propellantStore.propellantMassKg * 9.80665;
            attribute :>> requiresThreeAxis = true;

            bind thrust = thruster.thrust;
            bind powerIn = ppu.powerIn;
            bind cdhBus = ppu.cdhBus;
            interface ppu.thrusterSupply to thruster.supplyIn;
            interface propellantStore.feed to thruster.propellantIn;

            assert constraint propellantCompatibility { thruster.propellant == propellantStore.propellant }
        }

        part def PowerProcessingUnit {
            attribute massKg : Real = 0.15;
            attribute powerW : Real = 0.5;
            attribute volumeU : Real = 0.2;
            port powerIn : ~RegulatedPowerPort;
            port cdhBus : CommandTelemetryPort;
            port thrusterSupply : RegulatedPowerPort;
        }

        #specification part def ElectricThruster :> SpacecraftUnit {
            attribute specificImpulseS : Real;
            attribute propellant : PropellantType;
            port thrust : ThrustTransferPort;
            port supplyIn : ~RegulatedPowerPort;
            port propellantIn : ~PropellantFeedPort;
        }

        #design part def GriddedIonThruster :> ElectricThruster {
            attribute :>> massKg = 1.3;
            attribute :>> powerW = 5.5;
            attribute :>> volumeU = 0.8;
            attribute :>> specificImpulseS = 2100.0;
            attribute :>> propellant = PropellantType::xenon;
        }

        #design part def IodineRfThruster :> ElectricThruster {
            attribute :>> massKg = 1.0;
            attribute :>> powerW = 4.5;
            attribute :>> volumeU = 0.6;
            attribute :>> specificImpulseS = 1900.0;
            attribute :>> propellant = PropellantType::iodine;
        }

        #design part def FeepThruster :> ElectricThruster {
            attribute :>> massKg = 0.8;
            attribute :>> powerW = 3.5;
            attribute :>> volumeU = 0.5;
            attribute :>> specificImpulseS = 3500.0;
            attribute :>> propellant = PropellantType::indium;
        }

        #specification part def PropellantStorage :> SpacecraftUnit {
            attribute propellantMassKg : Real;
            attribute propellant : PropellantType;
            port feed : PropellantFeedPort;
        }

        #design part def XenonTank :> PropellantStorage {
            attribute :>> massKg = 0.8;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.4;
            attribute :>> propellantMassKg = 0.2;
            attribute :>> propellant = PropellantType::xenon;
        }

        #design part def IodineTank :> PropellantStorage {
            attribute :>> massKg = 0.5;
            attribute :>> powerW = 0.1;
            attribute :>> volumeU = 0.25;
            attribute :>> propellantMassKg = 0.25;
            attribute :>> propellant = PropellantType::iodine;
        }

        #design part def IndiumReservoir :> PropellantStorage {
            attribute :>> massKg = 0.35;
            attribute :>> powerW = 0.0;
            attribute :>> volumeU = 0.2;
            attribute :>> propellantMassKg = 0.22;
            attribute :>> propellant = PropellantType::indium;
        }

    }

    // =====================================================================================
    // Mission level: system blackbox and system greybox (configuration root)
    // =====================================================================================
    package Mission {
        private import OOSEM::OOSEM_Metadata::*;
        private import ScalarValues::*;
        private import SequenceFunctions::notEmpty;
        private import SequenceFunctions::isEmpty;
        private import RealFunctions::sum;
        private import Common::*;
        private import StructureThermal::*;
        private import Power::*;
        private import Gnc::*;
        private import DataHandling::*;
        private import Communications::*;
        private import Payloads::*;
        private import Propulsion::*;

        #specification part def EOSatellite {
            attribute massKg : Real;
            attribute groundSampleDistanceM : Real;
            attribute downlinkCapacityGbitPerDay : Real;
            attribute operatingAltitudeKm : Real;
            port launchRails : LaunchRailInterface;
            port ttcLink : RfSpaceLinkPort;
            port highRateLink[0..1] : RfSpaceLinkPort;
            port imagingAperture : OpticalAperturePort;
            port sunlight : SunlightPort;
        }

        #design part def EOSatelliteDesign :> EOSatellite {
            #specification part structure[1] : Structure;
            #specification part eps[1] : ElectricalPowerSystem;
            #specification part adcs[1] : AttitudeDeterminationControl;
            #specification part obc[1] : OnboardComputer;
            #specification part ttc[1] : TtcRadio;
            #specification part payload[1] : ImagingPayload;
            #specification part thermal[1] : ThermalControl;
            #specification part payloadDownlink[0..1] : PayloadDownlinkTransmitter;
            #specification part propulsion[0..1] : PropulsionSystem;
            #specification part gnss[0..1] : GnssReceiver;

            // ---- mission assumptions ----
            attribute contactSecondsPerDay : Real = 1920.0;   // 4 ground-station passes x 8 min
            attribute eclipseDurationH : Real = 0.6;          // worst-case LEO eclipse
            attribute systemMassMargin : Real = 1.15;         // 15 % system mass margin (early design phase)
            attribute harnessMassKg : Real = 0.3;             // inter-unit harness, brackets, fasteners
            attribute harnessVolumeU : Real = 0.12;           // harness routing and connector keep-out
            attribute distributionLossW : Real = 0.37;        // power distribution and harness losses
            attribute dragMakeUpDeltaVMs : Real = 250.0;      // delta-v to hold a <500 km orbit over the design life

            // ---- budgets derived from the subsystems' blackbox attributes ----
            attribute :>> massKg = harnessMassKg + sum((structure.massKg, eps.massKg, adcs.massKg, obc.massKg, ttc.massKg,
                payload.massKg, thermal.massKg, payloadDownlink.massKg, propulsion.massKg, gnss.massKg));
            attribute totalPowerW : Real = distributionLossW + sum((structure.powerW, eps.powerW, adcs.powerW, obc.powerW,
                ttc.powerW, payload.powerW, thermal.powerW, payloadDownlink.powerW, propulsion.powerW, gnss.powerW));
            attribute totalVolumeU : Real = harnessVolumeU + sum((structure.volumeU, eps.volumeU, adcs.volumeU, obc.volumeU,
                ttc.volumeU, payload.volumeU, thermal.volumeU, payloadDownlink.volumeU, propulsion.volumeU, gnss.volumeU));
            attribute downlinkRateMbps : Real = if notEmpty(payloadDownlink) ? payloadDownlink.dataRateMbps
                                                                            else ttc.dataRateMbps;
            attribute :>> downlinkCapacityGbitPerDay = downlinkRateMbps * contactSecondsPerDay / 1000.0;
            attribute :>> groundSampleDistanceM = payload.groundSampleDistanceM;
            attribute :>> operatingAltitudeKm = payload.designAltitudeKm;

            // ---- external interfaces ----
            bind launchRails = structure.launchRails;
            bind ttcLink = ttc.spaceLink;
            bind highRateLink = payloadDownlink.spaceLink;
            bind imagingAperture = payload.aperture;
            bind sunlight = eps.sunlight;

            // ---- regulated power distribution ----
            interface eps.powerOut to adcs.powerIn;
            interface eps.powerOut to obc.powerIn;
            interface eps.powerOut to ttc.powerIn;
            interface eps.powerOut to payload.powerIn;
            interface eps.powerOut to thermal.powerIn;
            interface eps.powerOut to payloadDownlink.powerIn;
            interface eps.powerOut to propulsion.powerIn;
            interface eps.powerOut to gnss.powerIn;

            // ---- command & telemetry bus (OBC is bus master) ----
            interface eps.cdhBus to obc.cdhBus;
            interface adcs.cdhBus to obc.cdhBus;
            interface ttc.cdhBus to obc.cdhBus;
            interface payload.cdhBus to obc.cdhBus;
            interface thermal.cdhBus to obc.cdhBus;
            interface payloadDownlink.cdhBus to obc.cdhBus;
            interface propulsion.cdhBus to obc.cdhBus;
            interface gnss.cdhBus to obc.cdhBus;

            // ---- payload data path, timing, heat ----
            interface payload.imageDataOut to obc.payloadDataIn;
            interface obc.downlinkDataOut to payloadDownlink.dataIn;
            interface gnss.pps to obc.ppsIn;
            interface payload.heatOut to thermal.heatIn;

            // ---- system-level dependencies between variation points ----
            assert constraint massBudget { massKg * systemMassMargin <= structure.maxLaunchMassKg }
            assert constraint volumeBudget { totalVolumeU <= structure.usableVolumeU }
            assert constraint powerBudget { totalPowerW <= eps.orbitAvgPowerW }
            assert constraint eclipseEnergy { totalPowerW * eclipseDurationH <= eps.usableEnergyWh }
            assert constraint heatRejection { totalPowerW <= thermal.maxHeatRejectionW }
            assert constraint solarArrayFit {
                eps.minStructureU <= structure.sizeU and structure.sizeU <= eps.maxStructureU
            }
            assert constraint payloadPointing { adcs.pointingAccuracyDeg <= payload.requiredPointingDeg }
            assert constraint downlinkPointing {
                isEmpty(payloadDownlink) or adcs.pointingAccuracyDeg <= payloadDownlink.requiredPointingDeg
            }
            // larger spacecraft need more stored momentum (inertia grows with form factor)
            assert constraint momentumStorage {
                adcs.threeAxis implies adcs.momentumCapacityMNms >= 2.5 * structure.sizeU
            }
            // what is acquired per day (after on-board reduction) must be downlinked per day
            assert constraint dataDownlink {
                payload.dailyDataGbit * obc.dataReductionFactor <= downlinkCapacityGbitPerDay
            }
            assert constraint onboardStorage { payload.dailyDataGbit <= obc.storageGbit }
            assert constraint payloadDataInterface { payload.needsSpaceWire implies obc.supportsSpaceWire }
            assert constraint detectorThermalStability { thermal.stabilityK <= payload.requiredThermalStabilityK }
            // below 500 km, drag decay must be compensated over the design life (impulse = delta-v x mass)
            assert constraint dragMakeUp {
                payload.designAltitudeKm >= 500.0 or
                (notEmpty(propulsion) and propulsion.totalImpulseNs >= dragMakeUpDeltaVMs * massKg)
            }
            // manoeuvres need on-board orbit determination and a pointable thrust vector
            assert constraint manoeuvreSupport {
                isEmpty(propulsion) or (notEmpty(gnss) and (adcs.threeAxis or not propulsion.requiresThreeAxis))
            }
            assert constraint georeferencing {
                (not payload.needsPreciseOrbit) or (notEmpty(gnss) and gnss.positionAccuracyM <= 2.0)
            }
        }
    }
}
