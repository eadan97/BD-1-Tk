use planilla
create procedure cargaDatos
as begin
  DECLARE @XML XML
  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/Feriados.xml', SINGLE_BLOB) AS BasicData)
  /*
       Cargar Feriados 
       */
      INSERT Feriado (Nombre, Fecha)
	        SELECT 
             Child.value('(@nombreferiado)[1]', 'varchar(50)'),
             Child.value('(@fecha)[1]', 'Date')
      FROM @XML.nodes('dataset/Feriados') AS N (Child)

  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/Puesto.xml', SINGLE_BLOB) AS BasicData)
  INSERT Puesto (Nombre)
	        SELECT 
             Child.value('(@nombre)[1]', 'varchar(25)')
      FROM @XML.nodes('dataset/Puesto') AS N (Child)

  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/SalarioXHora.xml', SINGLE_BLOB) AS BasicData)
  INSERT SalarioXHora (ID_Tipo_Jornada,ID_Puesto,Salario)
	        SELECT 
             Child.value('(@idPuesto)[1]', 'int'),
			 Child.value('(@idTipoJornada)[1]', 'int'),
			 Child.value('(@valorHora)[1]', 'Money')
      FROM @XML.nodes('dataset/SalarioxHora') AS N (Child)

  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/TipoJornadas.xml', SINGLE_BLOB) AS BasicData)
    INSERT TipoJornada (Nombre,Hora_Inicio,Hora_Fin)
	        SELECT 
             Child.value('(@nombre)[1]', 'Varchar(15)')			 
			 Child.value('(@HoraInicio)[1]', 'Time')	
			 Child.value('(@HoraFin)[1]', 'Time')	
      FROM @XML.nodes('dataset/TipoJornadas') AS N (Child)

--SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/TipoDeduccion.xml', SINGLE_BLOB) AS BasicData) --Tiene lo mismo que TipoMovimiento (?)
  SET @XML = (SELECT * FROM OPENROWSET(BULK '/home/datos/TipoMovimiento.xml', SINGLE_BLOB) AS BasicData)
    INSERT TipoMovimiento (Nombre)
	        SELECT 
             Child.value('(@nombre)[1]', 'Varchar(100)')			 
      FROM @XML.nodes('dataset/TipoMovimiento') AS N (Child)

END