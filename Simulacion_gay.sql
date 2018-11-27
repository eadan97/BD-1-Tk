create procedure Simulacion
as begin
  DECLARE @XML XML
  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/FechaOperacion V2.xml', SINGLE_BLOB) AS BasicData)


  -- Variables
  DECLARE @fecha_inicio date
  DECLARE @fecha_fin date

  DECLARE @low1 int
  DECLARE @high1 int
  --
  DECLARE @valorDocId numeric(12)
  DECLARE @idPuesto int
  DECLARE @idTipoJornada int
  DECLARE @horas int
  DECLARE @idPlanillaMensual int
  DECLARE @Nombre varchar(20)
  --DECLARE @Clave varchar(50)
  --DECLARE @Cero money
  --SET @Cero = 0
  --DECLARE @IdEstadoCuenta int
  DECLARE @horaEntrada time
  DECLARE @horaSalida time
  DECLARE @salarioPorHora money
  --DECLARE @QMaxATM1 int
  --DECLARE @QMaxManual1 int
  --DECLARE @QMaxATM2 int
  --DECLARE @QMaxManual2 int
  --DECLARE @MultaNegativo money
  --DECLARE @MultaMinimo money
  --DECLARE @MultaManual money
  --DECLARE @MultaATM money
  --DECLARE @TasaInteres int
  --
  ---- Tablas Variables
  DECLARE @EmpleadoAux TABLE(sec int IDENTITY (1, 1), valorDocId numeric(12), Nombre varchar(50), idPuesto int)
  DECLARE @AsistenciaAux TABLE(sec int IDENTITY (1, 1), Fecha date, IdObrero int, IdTipoJornada int, HoraEntrada time, HoraSalida time)
  --DECLARE @MovimientoAux TABLE(sec int IDENTITY(1,1), IdCuenta varchar(50), Monto money)
  --DECLARE @Movimientos TABLE(sec int IDENTITY(1,1), monto money, IdTipoMovimiento int, CodigoCuenta varchar(50), descripcion varchar(50))
  DECLARE @tabla_fechas TABLE(sec int IDENTITY (1, 1), fecha date)
  --DECLARE @EstadosCuenta TABLE(sec int IDENTITY(1,1), Id int, IdCuenta varchar(50), SaldoInicial money, SaldoFinal money,
  --                             SaldoMinimoCorte money, FechaCorte date, QopManual int, QopAT int)

  INSERT @tabla_fechas (fecha)
  SELECT CONVERT(VARCHAR(8), Child.value('(@fecha)[1]', 'date'), 3)
  FROM @XML.nodes('dataset/fechaOperacion') AS N (Child)

  SELECT @fecha_inicio = min(fecha), @fecha_fin = max(fecha) FROM @tabla_fechas
  --SET @fechaCorte = DATEADD(M,1, @fecha_inicio)


  --Inicio iteracion por fecha
  WHILE @fecha_inicio <= @fecha_fin
    BEGIN

      /* Agregar nnuevos empleados a tabla */
      INSERT @EmpleadoAux (Nombre, valorDocId, idPuesto)
      SELECT Child.value('(@nombre)[1]', 'varchar(50)'),
             Child.value('(@DocId)[1]', 'numeric(12)'),
             Child.value('(@idPuesto)[1]', 'int')
      FROM @XML.nodes('dataset/FechaOperacion/NuevoEmpleado') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@fecha', 'date')

      SELECT @low1 = min(sec), @high1 = max(sec) FROM @EmpleadoAux

      WHILE @low1 <= @high1
        BEGIN
          SELECT @valorDocId = C.valorDocId, @Nombre = C.Nombre, @idPuesto = C.idPuesto
          FROM @EmpleadoAux C
          WHERE C.sec = @low1
          INSERT INTO OBRERO (ID, Nombre, ID_PUESTO) VALUES (@valorDocId, @Nombre, @idPuesto)
          SET @low1 = @low1 + 1
        END

      INSERT @AsistenciaAux (Fecha, IdObrero, IdTipoJornada, HoraEntrada, HoraSalida)
      SELECT @fecha_inicio,
             Child.value('(@DocID)[1]', 'numeric(12)'),
             Child.value('(@idTipoJornada)[1]', 'int'),
             Child.value('(@HoraEntrada)[1]', 'time'),
             Child.value('(@HoraSalida)[1]', 'time')
      FROM @XML.nodes('dataset/FechaOperacion/Asistencia') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@Fecha', 'date')


      SELECT @low1 = min(sec), @high1 = max(sec) FROM @AsistenciaAux
      WHILE @low1 <= @high1
        BEGIN
          SELECT @valorDocId = C.IdObrero,
                 @idTipoJornada = C.IdTipoJornada,
                 @horaEntrada = C.HoraEntrada,
                 @horaSalida = C.HoraSalida
          FROM @AsistenciaAux C
          WHERE sec = @low1

          SELECT @salarioPorHora = TC.SALARIO
          FROM SALARIOXHORA TC
          WHERE TC.ID_TIPO_JORNADA = @idTipoJornada
            and TC.ID_PUESTO = @valorDocId

          /* Crea asistencia*/
          INSERT INTO ASISTENCIA (FECHA, ID_OBRERO, ID_TIPO_JORNADA, HORA_ENTRADA, HORA_SALIDA)
          SELECT @fecha_inicio, @valorDocId, @idTipoJornada, @horaEntrada, @horaSalida

          set @horas = datediff(hour, @horaEntrada, @horaSalida)

          IF (@horas < 0)
            begin
              set @horas = 24 + @horas
            end

          UPDATE PLANILLA_MENSUAL
          SET SALARIO_BRUTO = SALARIO_BRUTO + (@salarioPorHora * @horas)
              OUTPUT @idPlanillaMensual = inserted.ID
          WHERE ID_OBRERO = @valorDocId
            and MES = MONTH(@fecha_inicio)
            and ANNO = YEAR(@fecha_inicio)
          IF @@ROWCOUNT = 0
            INSERT INTO PLANILLA_MENSUAL ("ID_OBRERO", "SALARIO_BRUTO", "SALARIO_NETO", "MES", "ANNO")
                OUTPUT @idPlanillaMensual = inserted.ID
            values (@valorDocId, (@salarioPorHora * @horas), 0, MONTH(@fecha_inicio), YEAR(@fecha_inicio))
---------------------------------------------------------------------------
----------------------------VAMOS POR AQUI LA VERGA -----------------------
---------------------------------------------------------------------------
          --Estamos decifrando como hacer para poner la fecha para identificar la semana que corresponde del mes
          --luego de eso hay que Hacer lo mismo que se hace en planilla mensual, pero en la semanal
          -- Solo hay asistencias y nuevos maes.

          UPDATE PLANILLA_SEMANA
          SET SALARIO_BRUTO = SALARIO_BRUTO + (@salarioPorHora * @horas)
          WHERE ID_OBRERO = @valorDocId and
          MES = MONTH (@fecha_inicio) and
          ANNO = YEAR (@fecha_inicio)
          IF @@ROWCOUNT = 0
            INSERT INTO PLANILLA_SEMANA ("ID_OBRERO", "SALARIO_BRUTO", "SALARIO_NETO", "MES", "ANNO")
            values (@valorDocId, (@salarioPorHora * @horas), 0, MONTH(@fecha_inicio), YEAR(@fecha_inicio))


          /* Crea Estados de cuenta por cuenta */
          INSERT EstadoCuenta (IdCuenta, SaldoInicial, SaldoFinal, SaldoMinimoCorte, FechaCorte, QopManual, QopATM)
          SELECT @codCuenta, @Cero, @Cero, @Cero, DATEADD(M, 1, Child.value('../@fecha', 'date')), 0, 0
          FROM @XML.nodes('dataset/fechaOperacion/Cuenta') AS N (Child)
          WHERE @codCuenta = Child.value('(@codigoCuenta)[1]', 'varchar(50)')

          /* Crea Movimiento con Intereses por cuenta */
          INSERT MovimientoIntereses (IdTipoMovIntereses, IdCuenta, FechaMovimientoIntereses, Saldo, InteresDiario)
          SELECT 1, @codCuenta, DATEADD(M, 1, Child.value('../@fecha', 'date')), 0.0, @TasaInteres
          FROM @XML.nodes('dataset/fechaOperacion/Cuenta') AS N (Child)
          WHERE @codCuenta = Child.value('(@codigoCuenta)[1]', 'varchar(50)')
          /*
          INSERT MovimientoIntereses(IdTipoMovIntereses, IdCuenta, FechaMovimientoIntereses, Saldo, InteresDiario)
          SELECT 2, @codCuenta, Child.value('../@fecha', 'date') , 0.0, 0.0
          FROM @XML.nodes('dataset/fechaOperacion/Cuenta') AS N(Child)
          WHERE @codCuenta = Child.value('(@codigoCuenta)[1]', 'varchar(50)')
          */
          SET @low1 = @low1 + 1
        END

      /* Movimientos respecto fecha */
      INSERT @Movimientos (monto, IdTipoMovimiento, CodigoCuenta, descripcion)
      SELECT Child.value('(@monto)[1]', 'money'),
             Child.value('(@tipoMovimiento)[1]', 'int'),
             Child.value('(@codigoCuenta_Movimiento)[1]', 'varchar(50)'),
             Child.value('(@descripcion)[1]', 'varchar(50)')
      FROM @XML.nodes('dataset/fechaOperacion/Movimiento') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@fecha', 'date')

      SELECT @low1 = min(sec), @high1 = max(sec) FROM @Movimientos
      WHILE @low1 <= @high1
        BEGIN
          SELECT @Monto = M.monto,
                 @IdTipoCuenta = M.IdTipoMovimiento,
                 @codCuenta = M.CodigoCuenta,
                 @Nombre = M.descripcion
          FROM @Movimientos M
          WHERE sec = @low1

          SELECT @IdEstadoCuenta = EC.Id
          FROM EstadoCuenta EC
                 inner join Cuenta C on (EC.IdCuenta = C.CodigoCuenta)
          WHERE C.CodigoCuenta = @codCuenta

          INSERT INTO Movimiento (Monto,
                                  IdTipoMovimiento,
                                  IdCuenta,
                                  Descripcion,
                                  PostIp,
                                  PostTime,
                                  PostUser,
                                  FechaMovimiento,
                                  IdEstadoCuenta)
          VALUES (@Monto, @IdTipoCuenta, @codCuenta, @Nombre, 1, @fecha_inicio, 1, @fecha_inicio, @IdEstadoCuenta)

          IF (@IdTipoCuenta = 3 OR @IdTipoCuenta = 1)
            BEGIN
              UPDATE EstadoCuenta
              SET SaldoFinal += @Monto,
                  QopManual += 1
              WHERE IdCuenta = @codCuenta

            END
          IF (@IdTipoCuenta = 2 OR @IdTipoCuenta = 4)
            BEGIN
              UPDATE EstadoCuenta
              SET SaldoFinal += @Monto,
                  QopATM += 1
              WHERE IdCuenta = @codCuenta
            END
          /**/
          IF (@IdTipoCuenta = 1 OR @IdTipoCuenta = 2 OR @IdTipoCuenta = 6)
            BEGIN
              UPDATE Cuenta SET SaldoActual += @Monto WHERE CodigoCuenta = @codCuenta
            END
          ELSE BEGIN
            UPDATE Cuenta SET SaldoActual -= @Monto WHERE CodigoCuenta = @codCuenta
          END

          UPDATE MovimientoIntereses
          SET Saldo = Saldo + @Monto / 365 * (InteresDiario / 100)
          WHERE IdCuenta = @codCuenta

          SET @low1 = @low1 + 1
        END

      --====================================================================================================================================

      INSERT @EstadosCuenta (Id, IdCuenta, SaldoInicial, SaldoFinal, SaldoMinimoCorte, FechaCorte, QopManual, QopAT)
      SELECT Id, IdCuenta, SaldoInicial, SaldoFinal, SaldoMinimoCorte, FechaCorte, QopManual, QopATM
      FROM EstadoCuenta EC
      WHERE @fecha_inicio = FechaCorte

      SELECT @low1 = min(sec), @high1 = max(sec) FROM @EstadosCuenta

      WHILE @low1 <= @high1
        BEGIN

          SELECT @fechaCorte = EC.FechaCorte,
                 @codCuenta = EC.IdCuenta,
                 @saldoMin1 = EC.SaldoMinimoCorte,
                 @QMaxManual1 = EC.QopManual,
                 @QMaxATM1 = EC.QopAT,
                 @IdEstadoCuenta = EC.Id
          FROM @EstadosCuenta EC
          WHERE @low1 = EC.sec

          /* Multas */
          IF (@saldoMin1 < @saldoMin2)
            BEGIN
              UPDATE Cuenta SET SaldoActual = SaldoActual - @MultaMinimo WHERE Cuenta.CodigoCuenta = @codCuenta
            END

          IF (@QMaxManual1 > @QMaxManual2)
            BEGIN
              UPDATE Cuenta SET SaldoActual = SaldoActual - @MultaManual WHERE Cuenta.CodigoCuenta = @codCuenta
            END

          IF (@QMaxATM1 > @QMaxATM2)
            BEGIN
              UPDATE Cuenta SET SaldoActual = SaldoActual - @MultaATM WHERE Cuenta.CodigoCuenta = @codCuenta
            END

          SELECT @saldoMin1 = EC.SaldoFinal FROM @EstadosCuenta EC

          IF (@saldoMin1 < 0)
            BEGIN
              UPDATE Cuenta SET SaldoActual = SaldoActual - @MultaNegativo WHERE Cuenta.CodigoCuenta = @codCuenta
            END

          SET @fechaCorte = DATEADD(M, 1, @fecha_inicio)

          /* Aplica intereses */
          SELECT @TasaInteres = Saldo FROM MovimientoIntereses

          UPDATE Cuenta
          SET SaldoActual += @TasaInteres,
              InteresesAcumulados += @TasaInteres
          WHERE Cuenta.CodigoCuenta = @codCuenta

          UPDATE MovimientoIntereses
          SET Saldo                    = 0,
              FechaMovimientoIntereses = DATEADD(M, 1, @fecha_inicio)
          WHERE IdCuenta = @codCuenta

          INSERT INTO Movimiento (Monto,
                                  IdTipoMovimiento,
                                  IdCuenta,
                                  Descripcion,
                                  PostIp,
                                  PostTime,
                                  PostUser,
                                  FechaMovimiento,
                                  IdEstadoCuenta)
          VALUES (@TasaInteres,
                  6,
                  @codCuenta,
                  'Interes acumulado mensual',
                  1,
                  @fecha_inicio,
                  1,
                  @fecha_inicio,
                  @IdEstadoCuenta)

          /* Reninicia estado de cuenta*/
          UPDATE EstadoCuenta
          SET SaldoInicial = SaldoFinal,
              SaldoFinal   = @Cero,
              FechaCorte   = @fechaCorte,
              QopATM       = 0,
              QopManual    = 0
          WHERE Id = @low1

          SET @low1 = @low1 + 1
        END

      --------------------------------------------------------------
      SET @fecha_inicio = DATEADD(DD, 1, @fecha_inicio)
      DELETE FROM @ClienteAux;
      DELETE FROM @CuentaAux;
      DELETE FROM @Movimientos;
      DELETE FROM @EstadosCuenta;

      select * from Cliente
      select * from Cuenta
      select * from Movimiento
      select * from MovimientoIntereses
      select * from EstadoCuenta


    END
  --Fin
END