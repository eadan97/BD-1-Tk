use planilla
create procedure Simulacion
as begin
  DECLARE @XML XML
  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/FechaOperacion V2.xml', SINGLE_BLOB) AS BasicData)


  --TODO: Agregar numeros que estan "quemados" en el codigo
  -- Variables
  DECLARE @fecha_inicio date
  DECLARE @fecha_fin date

  DECLARE @low1 int
  DECLARE @high1 int
  --
  DECLARE @valorDocId numeric(12)
  DECLARE @idPuesto int
  DECLARE @idTipoJornada int
  DECLARE @idTipoMov int
  DECLARE @numeroDeVierneses int
  DECLARE @horas int
  DECLARE @tiempoNormal int
  DECLARE @fecha date
  DECLARE @idPlanillaMensual bigint
  DECLARE @idPlanillaSemanal bigint
  DECLARE @Nombre varchar(20)
  DECLARE @sabadoDePlanilla date
  DECLARE @viernesDePlanilla date

  DECLARE @idTipoDeduccion int
  DECLARE @valor int
  --SET @Cero = 0
  DECLARE @numeroDiaEnSemana int
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
  DECLARE @DeduccionAux TABLE(sec int IDENTITY (1, 1), DocId numeric(12), idTipoDeduccion int, Valor money)
  DECLARE @Bono TABLE(sec int IDENTITY (1, 1), DocId numeric(12), Monto money)
  DECLARE @tabla_fechas TABLE(sec int IDENTITY (1, 1), fecha date)
  DECLARE @cierrePlanillaSemAux TABLE(sec int IDENTITY (1, 1), idMensual bigint, idSemanal bigint, monto money, tipo_mov int, fecha date)

  DECLARE @IncapacidadAux TABLE(sec int IDENTITY (1, 1), DocId numeric(12), idTipoJornada int)
  --                             SaldoMinimoCorte money, FechaCorte date, QopManual int, QopAT int)

  INSERT @tabla_fechas (fecha)
  SELECT CONVERT(VARCHAR(8), Child.value('(@fecha)[1]', 'date'), 3)
  FROM @XML.nodes('dataset/fechaOperacion') AS N (Child)

  SELECT @fecha_inicio = min(fecha), @fecha_fin = max(fecha) FROM @tabla_fechas
  --SET @fechaCorte = DATEADD(M,1, @fecha_inicio)


  --Inicio iteracion por fecha
  WHILE @fecha_inicio <= @fecha_fin
    BEGIN

      set @sabadoDePlanilla = DATEADD(DAY, DATEDIFF(DAY, 5, @fecha_inicio) / 7 * 7, 5)
      set @viernesDePlanilla = DATEADD(d, 6 - DATEPART(dw, @fecha_inicio), @fecha_inicio)
      set @numeroDiaEnSemana = datepart(dw, @fecha_inicio)

      /*
       Cargar empleados en tabla auxiliar
       */
      INSERT OBRERO (ID, Nombre, ID_PUESTO)
      SELECT Child.value('(@DocId)[1]', 'numeric(12)'),
             Child.value('(@nombre)[1]', 'varchar(50)'),
             Child.value('(@idPuesto)[1]', 'int')
      FROM @XML.nodes('dataset/FechaOperacion/NuevoEmpleado') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@fecha', 'date')

      /*
      Cargar asistencias en tabla auxiliar
       */
      INSERT INTO ASISTENCIA (FECHA, ID_OBRERO, ID_TIPO_JORNADA, HORA_ENTRADA, HORA_SALIDA)
      SELECT @fecha_inicio,
             Child.value('(@DocID)[1]', 'numeric(12)'),
             Child.value('(@idTipoJornada)[1]', 'int'),
             Child.value('(@HoraEntrada)[1]', 'time'),
             Child.value('(@HoraSalida)[1]', 'time')
      FROM @XML.nodes('dataset/FechaOperacion/Asistencia') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@Fecha', 'date')




      -- Falta sumarle la cantidad de dinero ganada a la planilla, ahorita no se suma nada, solo se crea si no existe. Salarioxhora * horas
      MERGE INTO PLANILLA_MENSUAL PM
      USING (
            SELECT A.ID_OBRERO as id,
                   0 as sb,
                   0 as sn,
                   MONTH(@viernesDePlanilla) as mo,
                   YEAR(@viernesDePlanilla) as ye
            from ASISTENCIA A where FECHA=@fecha_inicio) AS reg
      ON (PM.MES = reg.mo
        and PM.ANNO = reg.ye
        and PM.ID_OBRERO = reg.id)
      --WHEN MATCHED THEN
      --  UPDATE SET nombre = reg.nombre, activo = reg.activo
      WHEN NOT MATCHED THEN
        INSERT (ID_OBRERO, SALARIO_BRUTO, SALARIO_NETO, MES, ANNO)
        VALUES (reg.id, reg.sb, reg.sn, reg.mo, reg.ye); -- OJO: Este punto y coma me lo pide por fuerza. No deberia ser necesario, pero mejor prevenir que lamentar


      MERGE INTO PLANILLA_SEMANA PS
      USING (
            SELECT PM.ID as id,
                   0 as sb,
                   0 as sn,
                   @sabadoDePlanilla as sa
            from ASISTENCIA A
            inner join PLANILLA_MENSUAL PM on (PM.ID_OBRERO=A.ID_OBRERO) where FECHA=@fecha_inicio and PM.MES = MONTH(@viernesDePlanilla) and PM.ANNO = YEAR(@viernesDePlanilla)) AS reg
      ON (PS.ID_PLANILLA_MENSUAL= reg.id
        and PS.FECHA = reg.sa)
      --WHEN MATCHED THEN
      --  UPDATE SET nombre = reg.nombre, activo = reg.activo
      WHEN NOT MATCHED THEN
        INSERT (ID_PLANILLA_MENSUAL, SALARIO_BRUTO, SALARIO_NETO, FECHA)
        VALUES (reg.id, reg.sb, reg.sn, reg.sa);

      --Movimiento de las horas normales de trabajo
      INSERT INTO MOVIMIENTO ("ID_PLANILLA_SEMANAL", "ID_OBRERO", "FECHA", "MONTO", "TIPO_MOVIMIENTO")
      SELECT S2.ID,--Aqui hace falta el id de la plantilla semanal
              A.ID_OBRERO,
             A.FECHA,
             CASE
                 WHEN datediff(hour, A.HORA_ENTRADA, A.HORA_SALIDA) < 0 then 24 - datediff(hour, A.HORA_ENTRADA, A.HORA_SALIDA),
                 ELSE datediff(hour, A.HORA_ENTRADA, A.HORA_SALIDA)
             END, 1
      FROM ASISTENCIA A
      INNER JOIN OBRERO O2 on A.ID_OBRERO = O2.ID
      INNER JOIN SALARIOXHORA SH on (SH.ID_TIPO_JORNADA =  A.ID_TIPO_JORNADA and SH.ID_PUESTO = O2.ID_PUESTO)
      inner join PLANILLA_MENSUAL MENSUAL3 on A.ID_OBRERO = MENSUAL3.ID_OBRERO
      inner join PLANILLA_SEMANA S2 on MENSUAL3.ID = S2.ID_PLANILLA_MENSUAL
      WHERE A.FECHA=@fecha_inicio and S2.FECHA = @sabadoDePlanilla

-------------Aqui termina lo hecho nuevo

      /*
       Cargar deducciones
       Se agrega el movimiento pero NO se descuenta (eso se hace en el cierre)
       */
      INSERT @DeduccionAux (DocId, idTipoDeduccion, Valor)
      SELECT Child.value('(@DocId)[1]', 'numeric(12)'),
             Child.value('(@idTipoDeduccion)[1]', 'int'),
             Child.value('(@valor)[1]', 'money')
      FROM @XML.nodes('dataset/FechaOperacion/NuevaDeuccion') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@Fecha', 'date')

      /*
       * Guardar deducciones en la base de datos
        Se agrega el movimiento pero NO se descuenta (eso se hace en el cierre)
       */
      SELECT @low1 = min(sec), @high1 = max(sec) FROM @DeduccionAux
      WHILE @low1 <= @high1
        BEGIN
          SELECT @valorDocId = M.DocId, @idTipoDeduccion = M.idTipoDeduccion, @valor = M.Valor
          FROM @DeduccionAux M
          WHERE sec = @low1

          SELECT @idPlanillaMensual = MENSUAL.ID
          FROM PLANILLA_SEMANA P
                 inner join PLANILLA_MENSUAL MENSUAL on P.ID_PLANILLA_MENSUAL = MENSUAL.ID
          WHERE MENSUAL.ID_OBRERO = @valorDocId
            and P.FECHA = @sabadoDePlanilla


          INSERT INTO MOVIMIENTO ("ID_PLANILLA_MENSUAL", "ID_OBRERO", "FECHA", "MONTO", "TIPO_MOVIMIENTO")
          VALUES (@idPlanillaMensual, @valorDocId, @fecha_inicio, @valor, @idTipoDeduccion + 5)

          --IF (@idTipoDeduccion = 1 OR @idTipoDeduccion= 2)
          --  BEGIN
          --    UPDATE PLANILLA_SEMANA
          --    SET SALARIO_BRUTO=SALARIO_BRUTO*(1-(@valor/100)),
          --        QopManual += 1
          --    WHERE IdCuenta = @codCuenta
          --  END
          --IF (@IdTipoCuenta = 2 OR @IdTipoCuenta = 4)
          --  BEGIN
          --    UPDATE EstadoCuenta
          --    SET SaldoFinal += @Monto,
          --        QopATM += 1
          --    WHERE IdCuenta = @codCuenta
          --  END
          --/**/
          --IF (@IdTipoCuenta = 1 OR @IdTipoCuenta = 2 OR @IdTipoCuenta = 6)
          --  BEGIN
          --    UPDATE Cuenta SET SaldoActual += @Monto WHERE CodigoCuenta = @codCuenta
          --  END
          --ELSE BEGIN
          --  UPDATE Cuenta SET SaldoActual -= @Monto WHERE CodigoCuenta = @codCuenta
          --END

        END

      /*
       Cargar bonos
       */
      INSERT @Bono (DocId, Monto)
      SELECT Child.value('(@DocId)[1]', 'numeric(12)'), Child.value('(@valor)[1]', 'money')
      FROM @XML.nodes('dataset/FechaOperacion/Bono') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@Fecha', 'date')

      /*
      Guardar bonos en base de datos
      En este caso si se agrega a la planilla
       */
      SELECT @low1 = min(sec), @high1 = max(sec) FROM @Bono
      WHILE @low1 <= @high1
        BEGIN
          SELECT @valorDocId = M.DocId, @valor = M.Monto FROM @Bono M WHERE sec = @low1

          SELECT @idPlanillaSemanal = P.ID
          FROM PLANILLA_SEMANA P
                 inner join PLANILLA_MENSUAL MENSUAL on P.ID_PLANILLA_MENSUAL = MENSUAL.ID
          WHERE MENSUAL.ID_OBRERO = @valorDocId
            and P.FECHA = @sabadoDePlanilla


          INSERT INTO MOVIMIENTO ("ID_PLANILLA_SEMANAL", "ID_OBRERO", "FECHA", "MONTO", "TIPO_MOVIMIENTO")
          VALUES (@idPlanillaSemanal,
                  @valorDocId,
                  @fecha_inicio,
                  @valor,
                  4) --4 porque es el valor del id de movimiento tipo bono en la tabla respectiva

          UPDATE PLANILLA_SEMANA SET SALARIO_NETO = SALARIO_NETO + @valor WHERE ID = @idPlanillaSemanal

        END


      /*
       Cargar incapacidades en tabla auxiliar
       */
      INSERT @IncapacidadAux (DocId, idTipoJornada)
      SELECT Child.value('(@DocId)[1]', 'numeric(12)'), Child.value('(@idTipoJornada)[1]', 'int')
      FROM @XML.nodes('dataset/FechaOperacion/Incapacidad') AS N (Child)
      WHERE @fecha_inicio = Child.value('../@Fecha', 'date')


      /*
      Cargar incapacidades en la base de datos
      Si se guardan los movimientos y se agrega en la planilla
       */
      SELECT @low1 = min(sec), @high1 = max(sec) FROM @IncapacidadAux
      WHILE @low1 <= @high1
        BEGIN
          SELECT @valorDocId = C.DocId, @idTipoJornada = C.idTipoJornada FROM @IncapacidadAux C WHERE C.sec = @low1

          --REgistro la incapacidad
          INSERT INTO INCAPACIDAD (ID_OBRERO, ID_TIPO_JORNADA, FECHA)
          VALUES (@valorDocId, @idTipoJornada, @fecha_inicio)
          SET @low1 = @low1 + 1

          --obtengo la planilla
          --SELECT @idPlanillaSemanal=P.ID
          --FROM PLANILLA_SEMANA P
          --  inner join PLANILLA_MENSUAL MENSUAL on P.ID_PLANILLA_MENSUAL = MENSUAL.ID
          --WHERE MENSUAL.ID_OBRERO=@valorDocId and P.FECHA=@sabadoDePlanilla


          Select @salarioPorHora = sxh.SALARIO * (0.6)
          from SALARIOXHORA sxh
                 inner join OBRERO o on sxh.ID_PUESTO = o.ID_PUESTO
          where sxh.ID_TIPO_JORNADA = @idTipoJornada


          IF (@idTipoJornada = 1)
            begin
              set @horas = 8
            end
          ELSE IF (@idTipoJornada = 2)
            begin
              set @horas = 5
            end
          ELSE begin
            set @horas = 11
          end

          UPDATE PLANILLA_MENSUAL
          SET SALARIO_BRUTO = SALARIO_BRUTO + (@salarioPorHora * @horas)
              OUTPUT @idPlanillaMensual = inserted.ID
          WHERE ID_OBRERO = @valorDocId
            and MES = MONTH(@sabadoDePlanilla)
            and ANNO = YEAR(@sabadoDePlanilla)
          IF @@ROWCOUNT = 0
            INSERT INTO PLANILLA_MENSUAL ("ID_OBRERO", "SALARIO_BRUTO", "SALARIO_NETO", "MES", "ANNO")
                OUTPUT @idPlanillaMensual = inserted.ID
            values (@valorDocId, (@salarioPorHora * @horas), 0, MONTH(@sabadoDePlanilla), YEAR(@sabadoDePlanilla))

          UPDATE PLANILLA_SEMANA
          SET SALARIO_BRUTO = SALARIO_BRUTO + (@salarioPorHora * @horas)
              OUTPUT @idPlanillaSemanal = inserted.ID
          WHERE ID_PLANILLA_MENSUAL = @idPlanillaMensual
            and FECHA = @sabadoDePlanilla
          IF @@ROWCOUNT = 0
            INSERT INTO PLANILLA_SEMANA (ID_PLANILLA_MENSUAL, "SALARIO_BRUTO", "SALARIO_NETO", FECHA)
                OUTPUT @idPlanillaSemanal = inserted.ID
            values (@valorDocId, (@salarioPorHora * @horas), 0, @sabadoDePlanilla)

          INSERT INTO MOVIMIENTO ("ID_PLANILLA_SEMANAL", "ID_OBRERO", "FECHA", "MONTO", "TIPO_MOVIMIENTO")
          VALUES (@idPlanillaSemanal,
                  @valorDocId,
                  @fecha_inicio,
                  (@salarioPorHora * @horas),
                  3) --3 porque es el valor del id de movimiento por incapacidad en la tabla respectiva


        END

      --------------------------------------------------------------
      --------------------------------------------------------------
      --------------------------------------------------------------
      --------------------------------------------------------------

      --Cierre
      IF (@numeroDiaEnSemana = 6)
        begin
          --Donde 6 es Viernes
          IF (@numeroDiaEnSemana =
              DATEADD(
                  DY,
                  DATEDIFF(
                      DY,
                      '1900-01-05',
                      DATEADD(
                          MM,
                          DATEDIFF(
                              MM, 0, @fecha_inicio), 30)) / 7 * 7, '1900-01-05')) --Es el ultimo viernes? Heh
            begin
              --Cierre mensual


            end
          else begin
            --Cierre semana
            insert into @cierrePlanillaSemAux (idMensual, idSemanal, monto, tipo_mov, fecha)
            SELECT PS.ID, PS.ID_PLANILLA_MENSUAL, MOV.MONTO, MOV.TIPO_MOVIMIENTO, MOV.FECHA
            From PLANILLA_SEMANA PS
                   inner join PLANILLA_MENSUAL MENSUAL2 on PS.ID_PLANILLA_MENSUAL = MENSUAL2.ID
                   inner join MOVIMIENTO MOV on PS.ID = MOV.ID_PLANILLA_MENSUAL
            where PS.FECHA = @sabadoDePlanilla --and @idTipoMov=6 or @idTipoMov=7

            SELECT @low1 = min(sec), @high1 = max(sec) FROM @cierrePlanillaSemAux
            while @low1 <= @high1
              BEGIN
                select @idPlanillaSemanal = c.idSemanal, @valor = C.monto, @idTipoMov = C.tipo_mov, @fecha = C.fecha
                from @cierrePlanillaSemAux C
                where C.sec = @low1
                --Agregar salario neto
                update PLANILLA_SEMANA set SALARIO_NETO = SALARIO_NETO + SALARIO_BRUTO where ID = @idPlanillaSemanal

                --Procesar deducciones porcentuales
                IF (@idTipoMov = 6 or @idTipoMov = 7)
                  begin
                    update PLANILLA_SEMANA
                    set SALARIO_NETO = SALARIO_NETO - (SALARIO_BRUTO * (@valor / 100))
                    where ID = @idPlanillaSemanal
                  end
                ELSE IF (@idTipoMov = 8 or @idTipoMov = 9) --procesar deducciones "fijas"
                  BEGIN
                    set @numeroDeVierneses = datediff(day, -3,
                                                      DATEADD(dd, -1, DATEADD(mm, DATEDIFF(mm, 0, GETDATE()) + 1, 0))
                                                      --ultimo dia
                                             ) / 7 - datediff(day, -2,
                                                              @fecha) --primer dia
                                                     / 7

                    update PLANILLA_SEMANA
                    set SALARIO_NETO = SALARIO_NETO - (@valor / @numeroDeVierneses) -- Todo: fix this. Baja toda la deduccion en una semana, coz reasons
                    where ID = @idPlanillaSemanal
                  end
              end

          end
        end


      SET @fecha_inicio = DATEADD(DD, 1, @fecha_inicio)

      DELETE FROM @EmpleadoAux
      DELETE FROM @AsistenciaAux
      DELETE FROM @DeduccionAux
      DELETE FROM @Bono
      DELETE FROM @tabla_fechas
      DELETE FROM @cierrePlanillaSemAux

      --select * from Cliente
      --select * from Cuenta
      --select * from Movimiento
      --select * from MovimientoIntereses
      --select * from EstadoCuenta


    END
  --Fin
END